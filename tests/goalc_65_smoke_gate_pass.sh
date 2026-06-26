#!/usr/bin/env bash
# GOALC #65: smoke gate pass. A passing real smoke test marks objective_gate
#            and close succeeds with no soft warnings — the happy path that
#            must not be broken by the gate.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-65
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "local_commit"' "$pf"
yq e -i '.environment.smoke_tests[0].command = "true"' "$pf"
yq e -i '.environment.smoke_tests[0].fidelity = "integration"' "$pf"
yq e -i '.environment.fidelity.enabled = true' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "passing smoke"

prepare_ready_to_close

out="$("$REPO_GS" close 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "close succeeds when smoke command passes"
else
  echo "$out" >&2
  bad "close should succeed when smoke command passes"
fi
printf '%s\n' "$out" | grep -q 'objective_gate=true' && ok "objective_gate=true reported" || bad "expected objective_gate=true"
if printf '%s\n' "$out" | grep -q 'RALPH_WIGGUM_WARNING'; then
  bad "no RALPH warning expected when gate passes"
else
  ok "no RALPH warning when objective gate passes"
fi

[ "$TESTS_FAIL" -eq 0 ]
