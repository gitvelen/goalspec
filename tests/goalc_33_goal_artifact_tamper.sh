#!/usr/bin/env bash
# GOALC #33: tampering the frozen goal.yaml artifact after freeze must make
#            `goalspec run` refuse execution (goal_artifact_hash binding).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-33
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

# sanity: state is prompt_ready and goal_artifact_hash is recorded
[ -n "$(yq e '.goal_artifact_hash // ""' "$REPO/.goalspec/active/state.yaml")" ] \
  && ok "freeze recorded goal_artifact_hash" || bad "freeze did not record goal_artifact_hash"

# tamper the frozen Goal artifact
printf '\nTAMPER\n' >> "$REPO/.goalspec/active/goal.yaml"

out="$("$REPO_GS" run 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && ! printf '%s\n' "$out" | grep -q '^GOALSPEC_RUN_ALLOWED: true'; then
  ok "run denied after goal.yaml tamper"
else
  bad "run allowed after goal.yaml tamper"
fi

[ "$TESTS_FAIL" -eq 0 ]
