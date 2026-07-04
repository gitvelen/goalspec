#!/usr/bin/env bash
# review.sh — generate fresh-context review prompt / apply review result.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

sub="${1:-}"; shift || true
case "$sub" in
  prompt)
    kind="${1:-intake}"
    case "$kind" in
      intake)
        cat <<EOF
# Intake review prompt (fresh context)

You are a fresh-context reviewer performing an INTAKE review. Do not read any
implementation conversation. Read ONLY:
  - .goalspec/active/goal.md
  - .goalspec/active/questions.yaml

Verify (GOALC #4):
  1. goal.md has all nine sections (Intent/Narrative/Success Model/Scope/Risk
     Scan/Goal Constraints/Sources and Decisions/Open Questions/Reopen Triggers).
  2. Intent states who, what scenario, what change.
  3. Narrative covers normal flow, failure paths, state changes, artifacts.
  4. Success Model has user_visible_success, system_observable_success,
     must_not_happen, minimum_acceptable_result, final_completion_signal.
  5. Scope has in_scope and out_of_scope.
  6. Risk Scan has all six subcategories with a conclusion OR a blocking question.
  7. No blocking open questions.
  8. No two reasonable interpretations that would lead to different implementations.

Emit a YAML document to stdout with:
  kind: intake
  result: pass | fail
  blocking_questions: []
  notes: |
    <your reasoning>
EOF
        ;;
      intake-capture)
        cf="$GOALSPEC_ROOT/active/intake-capture.md"
        sf="$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
        cnvf="$GOALSPEC_ROOT/active/intake-conversation.md"
        [ -f "$cf" ] || { echo "no intake-capture.md to review" >&2; exit 1; }
        [ -f "$cnvf" ] || { echo "no intake-conversation.md to review against" >&2; exit 1; }
        cat <<EOF
# Intake-capture review prompt (hot-context, adversarial)

Unlike the intake/contract reviews (fresh-context, form-only), THIS review is
the ONLY gate that checks whether the capture covers what the user ACTUALLY said.
It is hot-context on purpose: intent fidelity cannot be checked without reading
the conversation. Read:
  - .goalspec/active/intake-conversation.md   (ground truth of user intent)
  - .goalspec/active/intake-capture.md        (the digest under review)
  - .goalspec/active/constraint-suggestions.yaml (if present)

Stance: ASSUME the capture is incomplete or has drifted. Actively hunt for gaps.
Verify concretely (do NOT judge vaguely):
  1. coverage — every user-stated requirement, constraint, correction, and
     reversal in the conversation is reflected somewhere in the capture
     (Goal Candidate / User-visible Success / Confirmed Decisions / Scope /
     Excluded), or is explicitly marked Excluded with a reason. List each user
     point you cannot locate in the capture as a blocking finding.
  2. provenance — every entry under "Confirmed Decisions" carries a provenance
     tag: [user_said] (user explicitly decided in the conversation),
     [assistant_defaulted] (AI gave a default the user did not explicitly
     endorse), or [inferred] (AI deduced from code/context). Any untagged
     decision is a blocking finding.
  3. laundering — any [assistant_defaulted] or [inferred] decision that affects
     the goal, scope, or implementation direction MUST be an open_question, not
     a frozen Confirmed Decision. Flag each such case as blocking.
  4. downgrade — compare the capture's wording against the conversation for
     semantic weakening (e.g. a product positioning the user stated strongly
     that the capture reduces to a generic "notification"). Flag as blocking.
  5. conversational reversals — if the user reversed or corrected an earlier
     statement, the capture must reflect the FINAL position, not the superseded
     one. Flag any stale/superseded decision still present.

If intake-conversation.md is large (> ~1500 lines), do NOT skim or sample. Fan
out multiple sub-agents to read disjoint segments exhaustively, then merge
their findings — a lossy read of a long conversation is exactly the failure
mode this review exists to catch.

Emit a YAML document with:
  kind: intake-capture
  result: pass | fail
  blocking_questions: []
  notes: |
    For each checked user point: state where it landed in the capture (section +
    provenance) or that it is missing. Concrete entries only.
EOF
        ;;
      contract|criteria)
        cf="$GOALSPEC_ROOT/active/contract.yaml"
        if [ ! -f "$cf" ]; then
          echo "no contract.yaml to review" >&2; exit 1
        fi
        cat <<EOF
# Contract review prompt (fresh context)

You are a fresh-context reviewer performing a CONTRACT/CRITERIA review. Read ONLY:
  - .goalspec/active/contract.yaml
  - .goalspec/active/goal.md
  - .goalspec/project/*.yaml

Verify:
  - coverage — do NOT judge vaguely. Reconstruct a goal_branch × quality-dimension
    matrix and check every cell (the highest-value check; schema.sh cannot do it):
    * each Intent scenario and each Narrative flow (normal flow + every failure
      path + every state change) is covered by ≥1 criterion;
    * every must_not_happen entry maps to a dedicated negative criterion (not
      merged, not omitted);
    * every Risk Scan conclusion maps to a criterion or an explicit constraint;
    * every Success Model field (user_visible_success / system_observable_success
      / minimum_acceptable_result / final_completion_signal) is covered.
    List any uncovered branch as a blocking finding.
  - out_of_scope is reflected as hard constraints.
  - each criterion is decidable and not too weak/strong/vague.
  - each criterion's evidence_requirement_refs can prove that criterion.
  - allowed_paths / forbidden_paths express the execution scope boundary;
    allowed_paths are authorized impact domains, not exact file predictions;
    forbidden_paths are the precise "must not touch" set.
  - locked regressions are injected as required evidence.
  - no blocking compile question.
  (Note: presence of a final criterion is enforced by schema.sh at freeze, so it
  is not re-checked here.)

Emit a YAML document with:
  kind: contract
  result: pass | fail
  blocking_questions: []
  notes: |
    <reasoning>
EOF
        ;;
      *) echo "unknown review kind: $kind" >&2; exit 2 ;;
    esac
    ;;
  apply)
    file="${1:-}"
    [ -n "$file" ] || { echo "usage: goalspec review apply <file>" >&2; exit 2; }
    [ -f "$file" ] || { echo "review file not found: $file" >&2; exit 1; }
    kind="$(yq e '.kind' "$file")"
    result="$(yq e '.result' "$file")"
    case "$kind" in
      intake)
        # intake review applies to goal.md
        target_hash="$(goalspec_goal_hash)"
        # also enforce that goal.md structurally passes the gate
        if [ "$result" = "pass" ]; then
          if ! goalspec_schema_goal_md >/dev/null 2>&1; then
            err="$(goalspec_schema_goal_md 2>&1 >/dev/null)"
            echo "intake review cannot pass; goal.md schema errors:" >&2
            echo "$err" >&2
            exit 1
          fi
          # blocking questions: any unresolved blocking question blocks.
          nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$GOALSPEC_ROOT/active/questions.yaml" 2>/dev/null || echo 0)"
          if [ "${nblock:-0}" -gt 0 ]; then
            echo "intake review cannot pass: unresolved blocking questions present" >&2
            exit 1
          fi
          # goal.md is now the reviewed baseline: record its hash so a later edit
          # is detected as goal_changed. new_goal.sh sets the initial template
          # hash; without this update state.goal_hash stays stale forever and
          # goalspec_stale_goal_changed / status BLOCKERS misreport goal_changed.
          yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$GOALSPEC_ROOT/active/state.yaml"
        fi
        # intake review pass does not change the §4 lifecycle state; the goal
        # stays in spec_drafting until the contract is reviewed.
        ;;
      intake-capture)
        # intake-capture review binds to intake-capture.md content. It does not
        # advance lifecycle state; 'approve intake-package' gates on a passing
        # intake-capture review being present and fresh.
        target_hash="$(goalspec_intake_capture_hash)"
        ;;
      contract|criteria)
        target_hash="$(goalspec_contract_hash)"
        cur="$(yq e '.status' "$GOALSPEC_ROOT/active/state.yaml")"
        if [ "$result" = "pass" ]; then
          # blocking compile questions must be resolved
          nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$GOALSPEC_ROOT/active/questions.yaml" 2>/dev/null || echo 0)"
          if [ "${nblock:-0}" -gt 0 ]; then
            echo "contract review cannot pass: blocking questions unresolved" >&2
            exit 1
          fi
          # advance state: contract reviewed -> awaiting human confirmation to freeze
          if [ "$cur" = "spec_drafting" ]; then
            goalspec_state_set_status awaiting_human_confirmation
          fi
        fi
        ;;
      *) echo "unknown review kind in file: $kind" >&2; exit 1 ;;
    esac
    # Append to reviews.yaml
    rf="$GOALSPEC_ROOT/active/reviews.yaml"
    goalspec_init_list_file "$rf" reviews
    notes="$(yq e '.notes // ""' "$file")"
    tmp="$(mktemp)"
    bjson="$(yq -o=json '.blocking_questions // []' "$file")"
    yq -o=y --null-input \
      ".kind = \"$kind\"" > "$tmp"
    yq -i ".result = \"$result\"" "$tmp"
    yq -i ".target_hash = \"$target_hash\"" "$tmp"
    yq -i ".judged_at = \"$(goalspec_now)\"" "$tmp"
    yq -i ".blocking_questions = ${bjson}" "$tmp"
    goalspec_yq_set_scalar "$tmp" '.notes' "$notes"
    yq e -i ".reviews += load(\"$tmp\")" "$rf"
    /bin/rm -f "$tmp"
    echo "review applied: kind=$kind result=$result target_hash=$target_hash"
    ;;
  *)
    echo "usage: goalspec review prompt|apply [args]" >&2; exit 2
    ;;
esac
