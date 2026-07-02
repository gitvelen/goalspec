#!/usr/bin/env bash
# GOALC #36: /goalspec source may not bootstrap a goal before start, and is
# locked once the contract is FROZEN. Between end and freeze (spec_drafting)
# provenance can still grow — the hard lock is freeze, not end. The intake
# window itself closes at end (irreversible); only the source set may grow
# pre-freeze.
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

# --- source AFTER end but BEFORE freeze now SUCCEEDS: pre-freeze provenance
# can still grow (the v0004 transcript needed design/test docs sourced mid-
# compile, after intake end). The hard lock is freeze, not end. The intake
# window itself stays closed (end is irreversible) — only the source set grew. ---
echo "late" > "$REPO/late.txt"
if "$REPO_GS" source late.txt >/dev/null 2>"$TESTS_TMP_ROOT/src-after.err"; then
  ok "source accepted after end (pre-freeze)"
else
  bad "source rejected after end (pre-freeze): $(cat "$TESTS_TMP_ROOT/src-after.err")"
fi
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "source-after-end left intake window closed" \
  || bad "source-after-end mutated intake window state"

[ "$TESTS_FAIL" -eq 0 ]
