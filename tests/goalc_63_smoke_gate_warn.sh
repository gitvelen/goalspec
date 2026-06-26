#!/usr/bin/env bash
# GOALC #63: smoke gate soft mode. With no smoke_tests configured, close
#            succeeds but emits SMOKE_WARNING + RALPH_WIGGUM_WARNING — making
#            the all-soft close (the actual velentrade failure mode) visible
#            without blocking. Backward compatible.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-63
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "local_commit"' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "local_commit, no smoke_tests"

prepare_ready_to_close

out="$("$REPO_GS" close 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "soft close succeeds without smoke_tests (backward compatible)"
else
  echo "$out" >&2
  bad "soft close should succeed when no smoke_tests configured"
fi
printf '%s\n' "$out" | grep -q 'SMOKE_WARNING' && ok "SMOKE_WARNING emitted" || bad "expected SMOKE_WARNING"
printf '%s\n' "$out" | grep -q 'RALPH_WIGGUM_WARNING' && ok "RALPH_WIGGUM_WARNING emitted (all-soft close surfaced)" || bad "expected RALPH_WIGGUM_WARNING"

summ="$(yq e '.verification_summary' "$REPO/.goalspec/history/v0001/delivery.yaml")"
printf '%s\n' "$summ" | grep -q 'objective_gate=false' && ok "delivery summary records objective_gate=false" || bad "delivery summary missing objective_gate=false"

[ "$TESTS_FAIL" -eq 0 ]
