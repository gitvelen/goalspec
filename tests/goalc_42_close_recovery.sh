#!/usr/bin/env bash
# GOALC #42: V2 §8 — a failed close never remains in `closed`, and re-running
#            /goalspec close resumes from the checkpoint without re-creating the
#            main commit. Also covers #4: the real metadata commit SHA is
#            recorded, and a resumed close amends (never duplicates) it.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-42
install_fake_gh
setup_test_remote
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true

# Drive a goal all the way to ready_to_close.
prepare_ready_to_close

# Install a pre-push hook that fails on the SECOND push: close's first push is
# the main commit (succeeds), the second is the metadata push (fails) — exercising
# the post-closed-flip failure path that must roll back and stay resumable.
mkdir -p "$REPO/.git/hooks"
cat > "$REPO/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
c="$(cd "$(dirname "$0")" && pwd)/.pushcount"
n=$(cat "$c" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "$c"
if [ "$n" -ge 2 ]; then
  echo "simulated metadata-push failure (goalc_42)" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$REPO/.git/hooks/pre-push"

# --- Run 1: close must FAIL at the metadata push and NOT enter closed ---
if "$REPO_GS" close >/tmp/goalspec-close42-run1.out 2>&1; then
  bad "close succeeded despite simulated metadata-push failure"
else
  ok "close failed when metadata push failed"
fi
st="$(yq e '.status' "$REPO/.goalspec/active/state.yaml")"
[ "$st" = "closing" ] && ok "top-level status rolled back to closing (not closed)" || bad "status is '$st' after failed close (expected closing)"
[ "$(yq e '.close.status' "$REPO/.goalspec/active/state.yaml")" = "failed" ] \
  && ok "checkpoint status recorded as failed" || bad "checkpoint status not failed"
main_a="$(yq e '.close.main_commit // ""' "$REPO/.goalspec/active/state.yaml")"
[ -n "$main_a" ] && ok "main commit recorded before the failure" || bad "main commit missing after failed close"

# --- Run 2: remove the failure and resume — must reach closed, reuse main commit ---
/bin/rm -f "$REPO/.git/hooks/pre-push"
if "$REPO_GS" close >/tmp/goalspec-close42-run2.out 2>&1; then
  ok "resumed close succeeded"
else
  cat /tmp/goalspec-close42-run2.out >&2
  bad "resumed close failed"
fi
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] && ok "state is closed after resume" || bad "state not closed after resume"
main_b="$(yq e '.close.main_commit // ""' "$REPO/.goalspec/active/state.yaml")"
[ "$main_b" = "$main_a" ] && ok "main commit reused on resume (not re-created)" || bad "main commit changed on resume (was $main_a now $main_b)"
[ -n "$(yq e '.close.metadata_commit // ""' "$REPO/.goalspec/active/state.yaml")" ] \
  && ok "metadata commit SHA recorded (#4)" || bad "metadata commit not recorded"
[ -n "$(yq e '.close.pr_url // ""' "$REPO/.goalspec/active/state.yaml")" ] \
  && ok "PR URL preserved across resume" || bad "PR URL lost on resume"

# Exactly one metadata commit on the branch — resume amended, did not duplicate.
branch="$(yq e '.close.branch' "$REPO/.goalspec/active/state.yaml")"
meta_count="$(git -C "$REPO" log --oneline "$branch" 2>/dev/null | grep -c 'record delivery metadata' || true)"
[ "$meta_count" = "1" ] && ok "exactly one metadata commit after resume" || bad "metadata commit count=$meta_count (expected 1)"

[ "$TESTS_FAIL" -eq 0 ]
