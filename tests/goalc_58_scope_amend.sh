#!/usr/bin/env bash
# GOALC #58: scope amendments expand effective allowed_paths without changing
#            the frozen contract, while forbidden_paths still win.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-58
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p58"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
git add -A && git commit -q -m frozen-baseline
base_head="$(git rev-parse HEAD)"
BASE_HEAD="$base_head" yq e -i '.git.base_revision = strenv(BASE_HEAD)' "$REPO/.goalspec/active/state.yaml"
contract_before="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"

mkdir -p "$REPO/tests"
echo x > "$REPO/tests/new_test.txt"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check allowed tests/** before amendment"
else
  ok "scope-check blocks tests/** before amendment"
fi
if "$REPO_GS" scope-check --suggest >/tmp/goalspec-58-suggest.out 2>&1; then
  bad "scope-check --suggest unexpectedly passed"
elif grep -q 'tests/\*\*' /tmp/goalspec-58-suggest.out; then
  ok "scope-check --suggest proposes tests/**"
else
  bad "scope-check --suggest did not propose tests/**"
fi

"$REPO_GS" scope amend --allow 'tests/**' --reason 'tests belong to the same goal verification' >/tmp/goalspec-58-amend.out
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  ok "scope-check accepts tests/** after amendment"
else
  bad "scope-check still rejects tests/** after amendment"
fi
contract_after="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
[ "$contract_after" = "$contract_before" ] && ok "scope amendment does not change contract_hash" || bad "contract_hash changed after scope amendment"
yq e '.amendments[0].allowed_paths[]' "$REPO/.goalspec/active/scope-amendments.yaml" | grep -Fxq 'tests/**' \
  && ok "scope amendment records allowed path" || bad "scope amendment missing allowed path"

# forbidden_paths remain hard blockers.
fresh_initialized_repo goalc-58-forbidden
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
yq e -i '.forbidden_paths = ["secrets/**"]' "$REPO/.goalspec/active/contract.yaml"
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
git add -A && git commit -q -m frozen-baseline
base_head="$(git rev-parse HEAD)"
BASE_HEAD="$base_head" yq e -i '.git.base_revision = strenv(BASE_HEAD)' "$REPO/.goalspec/active/state.yaml"
mkdir -p "$REPO/secrets"
echo x > "$REPO/secrets/token.txt"
if "$REPO_GS" scope amend --allow 'secrets/**' --reason 'try forbidden path' >/tmp/goalspec-58-forbidden.out 2>&1; then
  bad "scope amend allowed a forbidden changed file"
else
  grep -q 'forbidden changed file' /tmp/goalspec-58-forbidden.out \
    && ok "scope amend rejects forbidden changed file" \
    || bad "scope amend failed without forbidden explanation"
fi

# A ready close package becomes stale after amendment and must be regenerated.
fresh_initialized_repo goalc-58-ready
prepare_ready_to_close
old_pkg_hash="$(yq e '.hashes.close_package_hash' "$REPO/.goalspec/active/close-package.yaml")"
mkdir -p "$REPO/tests"
echo x > "$REPO/tests/late_test.txt"
"$REPO_GS" scope amend --allow 'tests/**' --reason 'late verification file still supports current goal' >/dev/null
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "running" ] \
  && ok "scope amendment returns ready_to_close to running" \
  || bad "scope amendment did not return ready_to_close to running"
"$REPO_GS" run >/tmp/goalspec-58-rerun.out
grep -q 'CLOSE_PACKAGE_READY: true' /tmp/goalspec-58-rerun.out \
  && ok "run regenerates close package after scope amendment" \
  || bad "run did not regenerate close package after scope amendment"
new_pkg_hash="$(yq e '.hashes.close_package_hash' "$REPO/.goalspec/active/close-package.yaml")"
[ "$new_pkg_hash" != "$old_pkg_hash" ] && ok "close package hash changes after scope amendment" || bad "close package hash did not change"
yq e '.hashes.scope_hash // ""' "$REPO/.goalspec/active/close-package.yaml" | grep -q '^sha256:' \
  && ok "close package records scope_hash" || bad "close package missing scope_hash"
yq e '.scope.amendments[0].allowed_paths[]' "$REPO/.goalspec/active/close-package.yaml" | grep -Fxq 'tests/**' \
  && ok "close package records scope amendment" || bad "close package missing scope amendment"

# Legacy projects upgraded from before scope_hash should bootstrap instead of
# forcing a meaningless scope amendment.
fresh_initialized_repo goalc-58-legacy
prepare_ready_to_close
yq e -i 'del(.scope_hash) | .status = "running"' "$REPO/.goalspec/active/state.yaml"
if "$REPO_GS" close >/tmp/goalspec-58-legacy-close.out 2>&1; then
  bad "legacy close from running unexpectedly succeeded"
elif grep -q 'effective scope changed' /tmp/goalspec-58-legacy-close.out; then
  bad "legacy missing scope_hash was treated as real scope change"
else
  ok "legacy missing scope_hash does not block as scope change"
fi
"$REPO_GS" run >/tmp/goalspec-58-legacy-run.out
grep -q 'CLOSE_PACKAGE_READY: true' /tmp/goalspec-58-legacy-run.out \
  && ok "legacy missing scope_hash is bootstrapped by run" \
  || bad "legacy run did not bootstrap scope_hash"

[ "$TESTS_FAIL" -eq 0 ]
