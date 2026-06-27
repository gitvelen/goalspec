#!/usr/bin/env bash
# GOALC #36: /goalspec source may only add material to an OPEN intake window.
# Regression for the start/end intent boundary: source must not succeed before
# start (and must not bootstrap a goal) nor after end.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-36-source-window

# --- source BEFORE start must fail and must not bootstrap a goal ---
echo "seed" > "$REPO/seed.txt"
# start's worktree-clean gate (goalc_69) treats an untracked source file as a
# dirty worktree — commit it so the happy-path start below can open a window.
git -C "$REPO" add seed.txt && git -C "$REPO" commit -qm "seed source"
if "$REPO_GS" source seed.txt >/dev/null 2>"$TESTS_TMP_ROOT/src-before.err"; then
  bad "source accepted before start"
else
  ok "source rejected before start"
fi
if [ -f "$REPO/.goalspec/active/state.yaml" ]; then
  st="$(yq e '.status // "no_goal"' "$REPO/.goalspec/active/state.yaml")"
  [ "$st" = "no_goal" ] \
    && ok "source-before-start did not create a goal" \
    || bad "source-before-start bootstrapped a goal (status=$st)"
else
  ok "source-before-start did not create state.yaml"
fi

# --- happy path: start opens the window, source succeeds ---
"$REPO_GS" start "open window" >/dev/null
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "collecting" ] \
  && ok "start opens collecting window" \
  || bad "start did not open collecting window"
"$REPO_GS" source seed.txt >/dev/null \
  && ok "source accepted while collecting" \
  || bad "source rejected while collecting"

"$REPO_GS" end >/dev/null
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "end closes window" \
  || bad "end did not close window"

# --- source AFTER end must fail and must not mutate the closed window ---
echo "late" > "$REPO/late.txt"
if "$REPO_GS" source late.txt >/dev/null 2>"$TESTS_TMP_ROOT/src-after.err"; then
  bad "source accepted after end"
else
  ok "source rejected after end"
fi
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "source-after-end left window closed" \
  || bad "source-after-end mutated window state"

[ "$TESTS_FAIL" -eq 0 ]
