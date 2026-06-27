#!/usr/bin/env bash
# GOALC #69: `goalspec start` must refuse a dirty business worktree. intake's
#            `source` snapshots files into .goalspec/artifacts/intake/ (intake.sh
#            cp), so a dirty worktree corrupts intake provenance — and
#            freeze.sh:50 cannot catch it, because the dirty snapshot is frozen
#            at source time, before freeze ever runs. Cleanliness must therefore
#            be a precondition of intake, enforced as a hard gate at start, BEFORE
#            reset_active_workspace (so a rejected start never wipes active/).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ERR="$TESTS_TMP_ROOT/err69"

# --- Case A: dirty tracked business file -> blocked ---
fresh_initialized_repo goalc-69-tracked
mkdir -p "$REPO/src"
echo "v1" > "$REPO/src/app.py"
git -C "$REPO" add src/app.py && git -C "$REPO" commit -qm "add app"
echo "v2" >> "$REPO/src/app.py"
if "$REPO_GS" start "x" >/dev/null 2>"$ERR"; then
  bad "case A: start accepted with dirty tracked business file"
else
  ok "case A: start blocked with dirty tracked business file"
  grep -q "start blocked" "$ERR" && ok "case A: error says 'start blocked'" \
    || bad "case A: error missing 'start blocked'"
fi

# --- Case B: untracked business file -> blocked (source would snapshot it) ---
fresh_initialized_repo goalc-69-untracked
mkdir -p "$REPO/src"
echo "new" > "$REPO/src/fresh.py"   # untracked, not added
if "$REPO_GS" start "x" >/dev/null 2>"$ERR"; then
  bad "case B: start accepted with untracked business file"
else
  ok "case B: start blocked with untracked business file"
fi

# --- Case C: clean worktree -> start succeeds, reaches intake_collecting ---
fresh_initialized_repo goalc-69-clean
if "$REPO_GS" start "clean start" >/dev/null 2>"$ERR"; then
  ok "case C: start accepted with clean worktree"
  [ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "intake_collecting" ] \
    && ok "case C: reached intake_collecting" \
    || bad "case C: did not reach intake_collecting"
else
  bad "case C: start rejected despite clean worktree"; cat "$ERR" >&2
fi

# --- Case D: dirty framework file (AGENTS.md) -> NOT blocked ---
fresh_initialized_repo goalc-69-framework
echo "AGENTS" > "$REPO/AGENTS.md"
git -C "$REPO" add -f AGENTS.md && git -C "$REPO" commit -qm agents
echo "tweak" >> "$REPO/AGENTS.md"   # dirty, but a framework file -> excluded
git -C "$REPO" diff --name-only HEAD | grep -q '^AGENTS.md$' \
  || bad "case D setup: AGENTS.md not dirty/tracked"
if "$REPO_GS" start "x" >/dev/null 2>"$ERR"; then
  ok "case D: start not blocked by dirty framework file (AGENTS.md)"
else
  bad "case D: start wrongly blocked by framework file"; cat "$ERR" >&2
fi

# --- Case E: non-git fallback -> NOT blocked ---
# init.sh forces a git repo (init.sh:195), so a real project is always git;
# emulate the defensive case (.goalspec/ exists but .git is gone) to cover the
# worktree_clean `goalspec_git_in_repo || return 0` guard.
fresh_initialized_repo goalc-69-nongit
/bin/rm -rf "$REPO/.git"
if "$REPO_GS" start "non-git" >/dev/null 2>"$ERR"; then
  ok "case E: start not blocked in non-git project (fallback)"
else
  bad "case E: start blocked/failing in non-git project"; cat "$ERR" >&2
fi

[ "$TESTS_FAIL" -eq 0 ]
