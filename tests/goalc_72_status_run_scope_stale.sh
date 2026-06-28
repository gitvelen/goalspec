#!/usr/bin/env bash
# GOALC #72: status and run agree that scope_stale blocks RUN_ALLOWED.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-72
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p72"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" run >/dev/null

yq e -i '.scope_hash = "sha256:stale"' "$REPO/.goalspec/active/state.yaml"
status_out="$($REPO_GS status)"
echo "$status_out" | grep -q '^BLOCKERS: .*scope_stale' \
  && echo "$status_out" | grep -q '^RUN_ALLOWED: false' \
  && ok "status marks RUN_ALLOWED false when scope stale" \
  || bad "status did not block scope_stale consistently: $status_out"

if "$REPO_GS" run >"$tmp/run.out" 2>&1; then
  bad "run allowed execution despite scope_stale"
else
  grep -q 'effective scope changed since last approval' "$tmp/run.out" \
    && ok "run rejects same scope_stale blocker" \
    || bad "run rejected without scope_stale explanation: $(cat "$tmp/run.out")"
fi

[ "$TESTS_FAIL" -eq 0 ]
