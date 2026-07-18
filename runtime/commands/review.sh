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

After emitting the file, re-read its notes block to confirm no garbled or
fragmented text crept in — a known failure mode when emitting long YAML.
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
  2. provenance (citation-checked, not tag-trusted) — every [user_said] entry
     MUST carry a verbatim quote of the user's words that you can locate in
     intake-conversation.md (grep it). Mechanically verify each: does the quote
     actually appear in the conversation, AND was it the user initiating the
     decision (not "up to you / either is fine" delegation, not the AI's
     recommendation the user merely agreed to)? A [user_said] with no quote, a
     quote not found in the conversation, or a quote that is delegation/agreement
     rather than user-originated = blocking (downgrade to
     [assistant_defaulted]/[inferred] and move to Open Questions). Any untagged
     decision is also blocking.
  3. laundering — any [assistant_defaulted] or [inferred] decision that affects
     the goal, scope, or implementation direction MUST be an open_question, not
     a frozen Confirmed Decision. Flag each such case as blocking.
  4. downgrade — compare the capture's AND constraint-suggestions.yaml's wording
     against the conversation for semantic weakening (e.g. a product positioning
     the user stated strongly that the capture reduces to a generic
     "notification"), AND for level/atomicity drift between the capture and its
     constraint projection: a strong user acceptance signal that the constraints
     drop entirely, weaken hard→soft without a stated observability reason,
     split apart, or bury as implicit = blocking. Mechanically verify (grep):
     every [user_said]-tagged strong Acceptance Signal in the capture is
     referenced by >=1 constraint's source_refs via a CONCRETE id (a capture
     Decision id like [D8] or an Acceptance Signal id), not a vague
     "[conversation]"; an unreferenced strong signal, or one cited only by
     "[conversation]", is blocking.
  5. conversational reversals — if the user reversed or corrected an earlier
     statement, the capture must reflect the FINAL position, not the superseded
     one. Flag any stale/superseded decision still present.
  6. acceptance coverage — every workunit / capability listed in User-visible &
     System-observable Success must have a corresponding ACCEPTANCE POINT
     ("done when <observable condition>; fails when <observable condition>"),
     distinct from the capability itself. Flag as blocking: a capability with no
     acceptance point; a point that degenerated into mere existence ("page can
     load", "displays X", "no errors") rather than a success condition; or a
     top-level utility goal (e.g. "backtest decides whether to ship") with no
     acceptance point at all — even if that point must be kind: judgment. A
     capture with no Acceptance Signals section at all fails every capability.
  7. source-claim laundering — for any decision that drives scope/goal AND rests
     on an intake source (a sourced doc, not the user's own words), the capture
     MUST explicitly list the key claims it adopted from that source ("we adopted
     X from <source> §Y"). Source content is NOT ground truth — it is unverified
     input the AI chose to trust. Flag as blocking: a scope-driving decision
     resting on a source with no adopted-claims listed (without this the reviewer
     cannot tell what was trusted, and a domain error in the source — e.g. a
     wrong "scope-legitimacy" claim — sails through uncited).

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

After emitting the file, re-read its notes block to confirm no garbled or
fragmented text crept in — a known failure mode when emitting long YAML.
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
  - criterion interactions (the highest-leverage blind spot schema.sh cannot
    check — implicit conflicts the drafter did not declare). Build a criterion
    interaction view and report:
    * semantic conflicts — pairs of criteria that CANNOT both pass under the
      same implementation (e.g. one requires "an LLM failure aborts the workflow"
      while another requires "the end-to-end run completes with promote>0").
      For each, state the exact reason and whether it is resolvable by rewording,
      splitting the goal, or is a true spec contradiction. A true contradiction
      is a blocking finding — better caught here, before the run, than discovered
      mid-loop when the AI stalls and asks the human.
    * risky coupling — clusters of criteria sharing one evidence_requirement or
      one evidence source, where a single failure blocks many at once; recommend
      diversifying evidence or splitting criteria when the coupling is tight.
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

After emitting the file, re-read its notes block to confirm no garbled or
fragmented text crept in — a known failure mode when emitting long YAML.
EOF
        ;;
      *) echo "unknown review kind: $kind" >&2; exit 2 ;;
    esac
    ;;
  apply)
    file="${1:-}"
    [ -n "$file" ] || { echo "usage: goalspec review apply <file>" >&2; exit 2; }
    [ -f "$file" ] || { echo "review file not found: $file" >&2; exit 1; }
    if ! yq e '.' "$file" >/dev/null 2>&1; then
      echo "review file is not valid YAML: $file" >&2; exit 1
    fi
    kind="$(yq e '.kind' "$file")"
    result="$(yq e '.result' "$file")"
    case "$result" in
      pass|fail) ;;
      *) echo "review file has invalid result (expected pass|fail): ${result:-<empty>}" >&2; exit 1 ;;
    esac
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
