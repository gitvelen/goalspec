#!/usr/bin/env bash
# GOALC #15: blocking question blocks freeze; execution unknown must become
#            blocked/reopen_required, not be disguised as pass.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-15
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p15"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null

# Inject a blocking question.
cat > "$REPO/.goalspec/active/questions.yaml" <<'YML'
questions:
  - id: Q-BLOCK
    blocking: true
    status: open
    question: unresolved
YML

if "$REPO_GS" freeze >/dev/null 2>&1; then
  bad "freeze succeeded with unresolved blocking question"
else
  ok "freeze blocked by unresolved blocking question"
fi

# Resolve it; freeze should now succeed.
yq e -i '.questions[0].status = "resolved"' "$REPO/.goalspec/active/questions.yaml"
if "$REPO_GS" freeze >/dev/null 2>&1; then
  ok "freeze succeeds after blocking question resolved"
else
  bad "freeze still blocked after question resolved"
fi

[ "$TESTS_FAIL" -eq 0 ]
