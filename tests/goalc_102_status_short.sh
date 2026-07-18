#!/usr/bin/env bash
# GOALC #102: status --short prints a single grep-friendly line (STATE/iter/
#             outcome/blockers/unmet/NEXT) for cheap run-loop polling, without
#             the multi-line render or LOOP_CONTRACT block. Default unchanged.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-102
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

# ready_to_run: --short prints one line starting with STATE=ready_to_run + iter/outcome.
short_out="$("$REPO_GS" status --short 2>/dev/null)"
if printf '%s\n' "$short_out" | grep -qE '^STATE=ready_to_run iter=[0-9]+/[0-9]+ outcome=step '; then
  ok "status --short prints one-line STATE/iter/outcome at ready_to_run"
else
  bad "status --short output unexpected: $short_out"
fi

# --short emits exactly one line (no LOOP_CONTRACT, no multi-line block).
n_lines="$(printf '%s\n' "$short_out" | grep -c .)"
[ "$n_lines" -eq 1 ] && ok "status --short emits exactly one line" || bad "status --short emitted $n_lines lines"

# --oneline alias works identically.
alias_out="$("$REPO_GS" status --oneline 2>/dev/null)"
if printf '%s\n' "$alias_out" | grep -qE '^STATE=ready_to_run '; then
  ok "status --oneline alias works"
else
  bad "status --oneline alias failed: $alias_out"
fi

# Default (no flag) still prints the multi-line block.
multi_out="$("$REPO_GS" status 2>/dev/null)"
n_multi="$(printf '%s\n' "$multi_out" | grep -c .)"
[ "$n_multi" -gt 1 ] && ok "default status still multi-line ($n_multi lines)" || bad "default status collapsed to $n_multi lines"

[ "$TESTS_FAIL" -eq 0 ]
