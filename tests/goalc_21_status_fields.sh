#!/usr/bin/env bash
# GOALC #21: status and next output must include all nine fields.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

# next output must include all nine fields.
next_out="$("$REPO_GS" next)"
for fld in STATE NEXT_ACTION ROLE READ MAY_EDIT MUST_NOT_EDIT BLOCKERS CURRENT_WORK_UNIT COMPLETION_CONDITION; do
  if echo "$next_out" | /bin/grep -q "^${fld}:"; then
    :
  else
    bad "next missing $fld"
  fi
done
ok "next has all nine fields"

# status output and --json.
status_out="$("$REPO_GS" status)"
for fld in STATE NEXT_ACTION ROLE READ MAY_EDIT MUST_NOT_EDIT BLOCKERS CURRENT_WORK_UNIT COMPLETION_CONDITION; do
  echo "$status_out" | /bin/grep -q "^${fld}:" || bad "status missing $fld"
done
ok "status has all nine fields"

# --json mode parses and contains the same fields.
json_out="$("$REPO_GS" status --json)"
echo "$json_out" | yq e '.state' - >/dev/null || bad "status --json not parseable"
for k in state next_action role read may_edit must_not_edit blockers current_work_unit completion_condition; do
  echo "$json_out" | yq e ".$k" - >/dev/null 2>&1 || bad "status --json missing $k"
done
ok "status --json has all nine fields"

[ "$TESTS_FAIL" -eq 0 ]
