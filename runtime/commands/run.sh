#!/usr/bin/env bash
# run.sh — sole user-facing implementation gateway.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"
cf="$GOALSPEC_ROOT/active/contract.yaml"
pf="$GOALSPEC_ROOT/active/goal-driven-prompt.md"
qf="$GOALSPEC_ROOT/active/questions.yaml"

deny() {
  echo "GOALSPEC_RUN_ALLOWED: false" >&2
  echo "BLOCKER: $*" >&2
  echo "NEXT_USER_ACTION: Review, confirm, regenerate the Goal-Driven Prompt, or run /goalspec reopen <reason> as appropriate." >&2
  exit 1
}

[ -f "$cf" ] || deny "contract.yaml is missing; Goal, Criteria, and Constraints are not frozen"
[ "$(yq e '.status // ""' "$cf")" = "frozen" ] || deny "Goal, Criteria, and Constraints are not frozen"

[ -f "$GOALSPEC_ROOT/active/goal.yaml" ] || deny "frozen Goal artifact is missing"
[ -f "$GOALSPEC_ROOT/active/criteria.yaml" ] || deny "frozen Criteria artifact is missing"
[ -f "$GOALSPEC_ROOT/active/constraints.yaml" ] || deny "frozen Constraints artifact is missing"

[ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] || deny "frozen Goal is stale"
[ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] || deny "frozen Criteria are stale"
[ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ] || deny "frozen Constraints are stale"
[ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] || deny "frozen contract is stale"

nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$qf" 2>/dev/null || echo 0)"
[ "${nblock:-0}" -eq 0 ] || deny "blocking questions are unresolved"

[ -f "$pf" ] || deny "Goal-Driven Prompt is missing"
[ "$(yq e '.prompt_hash // ""' "$state_file")" = "$(goalspec_prompt_hash)" ] || deny "Goal-Driven Prompt is stale"

if [ "$(yq e '.status' "$state_file")" = "prompt_ready" ]; then
  goalspec_state_set_status running
fi

cat <<EOF
GOALSPEC_RUN_ALLOWED: true
PROMPT_FILE: .goalspec/active/goal-driven-prompt.md
PROMPT_HASH: $(goalspec_prompt_hash)
READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true

EOF
cat "$pf"
