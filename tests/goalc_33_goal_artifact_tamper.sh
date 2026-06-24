#!/usr/bin/env bash
# GOALC #33: tampering the frozen Goal (goal.md) after freeze must make
#            `goalspec run` refuse execution (goal_hash binding). The frozen
#            Goal is goal.md itself; there is no longer a separate goal.yaml.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-33
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

# sanity: freeze recorded the goal_hash baseline
[ -n "$(yq e '.goal_hash // ""' "$REPO/.goalspec/active/state.yaml")" ] \
  && ok "freeze recorded goal_hash" || bad "freeze did not record goal_hash"

# tamper the frozen Goal (goal.md) after freeze
printf '\nTAMPER\n' >> "$REPO/.goalspec/active/goal.md"

out="$("$REPO_GS" run 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && ! printf '%s\n' "$out" | grep -q '^GOALSPEC_RUN_ALLOWED: true'; then
  ok "run denied after goal.md tamper"
else
  bad "run allowed after goal.md tamper"
fi

[ "$TESTS_FAIL" -eq 0 ]
