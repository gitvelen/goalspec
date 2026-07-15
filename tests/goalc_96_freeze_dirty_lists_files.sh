#!/usr/bin/env bash
# GOALC #96: when freeze is blocked by a dirty business worktree, the failure
#            message names the offending files (not just "has uncommitted
#            changes"), so the user knows exactly what to commit/stash/gitignore.
#            Listing files does NOT relax the gate — freeze is still blocked.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac }

fresh_initialized_repo goalc-96
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation

# Dirty business file with a recognizable name.
mkdir -p "$REPO/src"; echo x > "$REPO/src/feature_flag.txt"
err="$("$REPO_GS" freeze 2>&1 >/dev/null || true)"
if contains "$err" "src/feature_flag.txt"; then
  ok "freeze dirty error names the offending file"
else
  bad "freeze dirty error does not name the file: $err"
fi
# The gate is unchanged — still blocked.
if "$REPO_GS" freeze >/dev/null 2>&1; then
  bad "freeze succeeded with business dirty"
else
  ok "freeze still blocked with business dirty"
fi

[ "$TESTS_FAIL" -eq 0 ]
