#!/usr/bin/env bash
# GOALC #64: smoke gate enforce mode. With fidelity.enforce_on_close=true, a
#            failing smoke command fails close — the velentrade case where a
#            real end-to-end gate catches shipped bugs.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-64
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "local_commit"' "$pf"
yq e -i '.environment.smoke_tests[0].command = "false"' "$pf"
yq e -i '.environment.smoke_tests[0].fidelity = "integration"' "$pf"
yq e -i '.environment.fidelity.enabled = true' "$pf"
yq e -i '.environment.fidelity.enforce_on_close = true' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "failing smoke + enforce"

prepare_ready_to_close

if "$REPO_GS" close >/tmp/goalspec-56.out 2>&1; then
  bad "enforce close should FAIL when a smoke command fails"
else
  ok "enforce close fails when a smoke command fails"
fi
grep -q 'smoke gate failed' /tmp/goalspec-56.out && ok "failure reason cites smoke gate" || bad "failure reason missing smoke gate"
[ "$(yq e '.close.status // ""' "$REPO/.goalspec/active/state.yaml")" = "failed" ] && ok "state.close.status=failed" || bad "state.close.status not failed"

[ "$TESTS_FAIL" -eq 0 ]
