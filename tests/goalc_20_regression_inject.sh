#!/usr/bin/env bash
# GOALC #20: locked regression injected as required evidence in subsequent
#            contract; waiver requires human approval.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-20
# Seed a locked regression in the long-term suite.
cat > "$REPO/.goalspec/project/regression-suite.yaml" <<'YML'
regressions:
  - id: REG-PREV-001
    description: previous bug
    replay_command: t
    expected_result: "exit_code == 0"
    status: locked
    locked_scope: src/**
YML
git add -A && git commit -q -m locked-regression

"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null

# Compile writes contract; compiler must inject locked regression as required.
# We verify the freeze step warns about locked regressions not in required_regressions.
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
# minimal contract above has empty required_regressions; verify freeze emits a warning.
tmp="$TESTS_TMP_ROOT/p20"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
out="$("$REPO_GS" freeze 2>&1)"
if echo "$out" | /bin/grep -qi 'locked regression'; then
  ok "freeze flags locked regression injection"
else
  bad "freeze did not flag locked regression injection"
fi

# Now test the regression waiver approval path: an approval entry can be recorded.
"$REPO_GS" approve regression-waiver REG-PREV-001 >/dev/null && ok "regression-waiver approval recorded"

# Without approval, the approval entry should not exist; we tested existence above.
# Verify approve rejects unknown kind.
if "$REPO_GS" approve bad-kind >/dev/null 2>&1; then
  bad "approve accepted unknown kind"
else
  ok "approve rejected unknown kind"
fi

[ "$TESTS_FAIL" -eq 0 ]
