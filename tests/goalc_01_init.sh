#!/usr/bin/env bash
# GOALC #1: empty git repo + goalspec init -> full .goalspec/, short AGENTS/CLAUDE,
#            and `goalspec status` gives a clear NEXT_ACTION.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-01
ok "init in empty git repo"

[ -d "$REPO/.goalspec/runtime" ] || bad "missing runtime/"
[ -d "$REPO/.goalspec/ai" ]       || bad "missing ai/"
[ -d "$REPO/.goalspec/project" ]  || bad "missing project/"
[ -d "$REPO/.goalspec/active" ]   || bad "missing active/"
[ -f "$REPO/AGENTS.md" ]          || bad "missing AGENTS.md"
[ -f "$REPO/CLAUDE.md" ]          || bad "missing CLAUDE.md"
[ -x "$REPO_GS" ]                 || bad "goalspec not executable"

# status must give a NEXT_ACTION line that points at new-goal (no active goal yet).
status_out="$("$REPO_GS" status)"
echo "$status_out" | /bin/grep -q '^NEXT_ACTION:' || bad "status missing NEXT_ACTION"
echo "$status_out" | /bin/grep -qi 'new-goal'     || bad "NEXT_ACTION does not mention new-goal"

[ "$TESTS_FAIL" -eq 0 ]
