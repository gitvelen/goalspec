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
  - every core goal scenario is covered by criteria.
  - every must_not_happen becomes a negative criterion.
  - out_of_scope is reflected as hard constraints.
  - each criterion is decidable and not too weak/strong/vague.
  - each criterion's evidence_requirement_refs can prove that criterion.
  - allowed_paths / forbidden_paths express the execution scope boundary;
    allowed_paths are wide globs (a too-narrow set forces a mid-change reopen),
    forbidden_paths are the precise "must not touch" set.
  - locked regressions are injected as required evidence.
  - there is a final criterion.
  - no blocking compile question.

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
    yq -i ".notes = \"$notes\"" "$tmp"
    yq e -i ".reviews += load(\"$tmp\")" "$rf"
    /bin/rm -f "$tmp"
    echo "review applied: kind=$kind result=$result target_hash=$target_hash"
    ;;
  *)
    echo "usage: goalspec review prompt|apply [args]" >&2; exit 2
    ;;
esac
