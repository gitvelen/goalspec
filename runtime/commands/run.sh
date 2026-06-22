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

state="$(yq e '.status // "no_goal"' "$state_file" 2>/dev/null || echo "no_goal")"
[ "$state" != "reopen_required" ] || deny "state is reopen_required; review the reopen impact, revise goal.md and/or contract.yaml, then re-review, re-approve, and freeze before running again"
# capped blocks the loop — UNLESS all Criteria already pass, in which case run
# must still generate the close package so the human can /goalspec close.
if [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" = "capped" ] \
  && ! goalspec_close_completion_gate >/dev/null 2>&1; then
  deny "run-loop is capped (reached max_iterations); run /goalspec close if Criteria are met, or /goalspec reopen to reset"
fi
# stalled blocks the loop the same way — UNLESS all Criteria already pass.
# stalled means the loop spun without progress (a likely spec defect), so the
# recovery hint steers toward reopen rather than just "raise the cap".
if [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" = "stalled" ] \
  && ! goalspec_close_completion_gate >/dev/null 2>&1; then
  deny "run-loop is stalled (no progress for stall_threshold rounds — likely a spec defect); run /goalspec reopen to revise, or /goalspec close if Criteria are met"
fi

[ -f "$cf" ] || deny "contract.yaml is missing; Goal, Criteria, and Constraints are not frozen"
[ "$(yq e '.status // ""' "$cf")" = "frozen" ] || deny "Goal, Criteria, and Constraints are not frozen"

[ -f "$GOALSPEC_ROOT/active/goal.yaml" ] || deny "frozen Goal artifact is missing"
[ -f "$GOALSPEC_ROOT/active/criteria.yaml" ] || deny "frozen Criteria artifact is missing"
[ -f "$GOALSPEC_ROOT/active/constraints.yaml" ] || deny "frozen Constraints artifact is missing"

[ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] || deny "frozen Goal is stale"
[ "$(yq e '.goal_artifact_hash // ""' "$state_file")" = "$(goalspec_goal_artifact_hash)" ] || deny "frozen Goal artifact is stale"
[ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] || deny "frozen Criteria are stale"
[ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ] || deny "frozen Constraints are stale"
[ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] || deny "frozen contract is stale"

nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$qf" 2>/dev/null || echo 0)"
[ "${nblock:-0}" -eq 0 ] || deny "blocking questions are unresolved"

[ -f "$pf" ] || deny "Goal-Driven Prompt is missing"
[ "$(yq e '.prompt_hash // ""' "$state_file")" = "$(goalspec_prompt_hash)" ] || deny "Goal-Driven Prompt is stale"

case "$state" in
  ready_to_run|prompt_ready)
    goalspec_state_set_status running
    ;;
  running|ready_to_close)
    :
    ;;
  *)
    deny "state is not ready_to_run or running"
    ;;
esac

# judgment-kind stop condition: once every machine criterion has a pass
# verdict, the loop must NOT blindly retry the remaining judgment-kind
# criteria — those need human/Master resolution, not Subagent iteration
# (Akshy: judgment work loops only to the degree the checker can confirm the
# result). Checked only after machine criteria are satisfied, to avoid a
# deadlock where judgment evidence depends on machine work finishing first.
machine_unmet=""; judgment_unmet=""
while IFS= read -r cid; do
  [ -z "$cid" ] && continue
  k="$(yq e ".criteria[] | select(.id == \"$cid\") | .kind // \"machine\"" "$cf")"
  if goalspec_close_criterion_has_fresh_pass "$cid"; then
    :
  elif [ "$k" = "judgment" ]; then
    judgment_unmet="${judgment_unmet}${cid} "
  else
    machine_unmet="${machine_unmet}${cid} "
  fi
done <<<"$(goalspec_close_required_criteria_ids)"
if [ -z "$machine_unmet" ] && [ -n "$judgment_unmet" ]; then
  deny "machine criteria satisfied; remaining judgment-kind criteria require human/Master resolution, not blind Subagent retry: $judgment_unmet"
fi

if goalspec_close_completion_gate >/dev/null 2>&1; then
  goalspec_close_write_package
  goalspec_state_set_status ready_to_close
  cat <<EOF
GOALSPEC_RUN_ALLOWED: true
CLOSE_PACKAGE_READY: true
CLOSE_PACKAGE_FILE: .goalspec/active/close-package.yaml
CLOSE_PACKAGE_HASH: $(goalspec_close_package_hash)
NEXT_USER_ACTION: Review the close package, then run /goalspec close to archive, commit, push, and open a PR.

验收已通过，已生成 close package。
运行 /goalspec close 后，我会应用长期记忆、归档 history、commit、push 并创建 PR。
EOF
  exit 0
fi

cat <<EOF
GOALSPEC_RUN_ALLOWED: true
PROMPT_FILE: .goalspec/active/goal-driven-prompt.md
PROMPT_HASH: $(goalspec_prompt_hash)
READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true

EOF
cat "$pf"
