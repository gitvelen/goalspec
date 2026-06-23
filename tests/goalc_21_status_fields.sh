#!/usr/bin/env bash
# GOALC #21: status output is goal-driven and does not expose work units.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

has_line_prefix() {
  case "$1" in *$'\n'"$2"*|"$2"*) return 0;; *) return 1;; esac
}

fresh_initialized_repo goalc-21
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p21"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

# status output and --json.
status_out="$("$REPO_GS" status)"
for fld in STATE GOAL FROZEN PROMPT_READY RUN_ALLOWED CLOSE_READY NEEDS_HUMAN_CONFIRMATION BLOCKERS CLOSE_BLOCKERS UNMET_CRITERIA NEXT_USER_ACTION; do
  has_line_prefix "$status_out" "${fld}:" || bad "status missing $fld"
done
if case "$status_out" in *CURRENT_WORK_UNIT*) true;; *) false;; esac; then
  bad "status exposes current work unit"
else
  ok "status hides work units"
fi
ok "status has goal-driven fields"

# --json mode parses and contains the same fields.
json_out="$("$REPO_GS" status --json)"
echo "$json_out" | yq e '.state' - >/dev/null || bad "status --json not parseable"
for k in state goal frozen prompt_ready run_allowed close_ready needs_human_confirmation blockers close_blockers unmet_criteria next_user_action; do
  echo "$json_out" | yq e ".$k" - >/dev/null 2>&1 || bad "status --json missing $k"
done
ok "status --json has goal-driven fields"

[ "$TESTS_FAIL" -eq 0 ]
