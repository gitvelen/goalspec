#!/usr/bin/env bash
# GOALC #9: freeze fails if business code dirty; .goalspec/active compiled
#            changes should NOT be misjudged as business dirty.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-09
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p9"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null

# Make business code dirty.
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
if "$REPO_GS" freeze >/dev/null 2>&1; then
  bad "freeze succeeded with business dirty"
else
  ok "freeze blocked with business dirty"
fi

# Clean business; only .goalspec/active is changed (the contract itself).
/bin/rm -rf "$REPO/src"
if "$REPO_GS" freeze >/dev/null 2>&1; then
  ok "freeze succeeds when only .goalspec/active compiled files changed"
else
  bad "freeze blocked when only .goalspec/active is dirty"
fi

[ "$TESTS_FAIL" -eq 0 ]
