#!/usr/bin/env bash
# GOALC #3: without intake review pass / goal approval, compile/freeze/run blocked.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-03
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"

# compile without intake review -> blocked
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile succeeded without intake review"
else
  ok "compile blocked without intake review"
fi

# apply a passing intake review (no goal approval yet)
tmp="$TESTS_TMP_ROOT/p"
mkdir -p "$tmp"
cat > "$tmp/intake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/intake.yaml" >/dev/null

# compile without goal approval -> still blocked
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile succeeded without goal approval"
else
  ok "compile blocked without goal approval"
fi

# approve goal, then compile should succeed and produce a draft contract path
"$REPO_GS" approve goal >/dev/null
"$REPO_GS" compile >/dev/null && ok "compile succeeds after intake+goal approval"

# now contract is still draft; freeze should be blocked (no contract review, no contract approval)
if "$REPO_GS" freeze >/dev/null 2>&1; then
  bad "freeze succeeded without contract review+approval"
else
  ok "freeze blocked without contract review+approval"
fi

# run on non-frozen contract -> blocked (no frozen Goal-Driven Prompt)
if "$REPO_GS" run >/dev/null 2>&1; then
  bad "run succeeded before freeze"
else
  ok "run blocked before freeze"
fi

[ "$TESTS_FAIL" -eq 0 ]
