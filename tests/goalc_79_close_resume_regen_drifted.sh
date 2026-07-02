#!/usr/bin/env bash
# GOALC #79: resuming a close whose changed_files_hash drifted (e.g. a
#            verification artifact changed since the package was generated)
#            must regenerate the close package in place and reach closed —
#            WITHOUT forcing a hand-edit of state.yaml back to ready_to_run
#            (the v0004 transcript's sed hack). First-time close still fails
#            strict so genuine drift is surfaced.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-79
install_fake_gh
setup_test_remote
( cd "$REPO" && git push -u origin main >/dev/null 2>&1 ) || ( cd "$REPO" && git push -u origin master >/dev/null 2>&1 ) || true

prepare_ready_to_close

# prepare_ready_to_close created src/a.txt (untracked business) and generated
# the close package (changed_files_hash = H1). Drift the fingerprint AFTER
# package generation so the close-time recheck sees H1 != current H2.
echo "drift" >> "$REPO/src/a.txt"

# Run 1: first-time close (is_resume=false) — must fail strict on the drift.
if "$REPO_GS" close >/tmp/goalspec-79-run1.out 2>&1; then
  bad "first close succeeded despite changed_files drift (should fail strict)"
else
  ok "first close failed strict on changed_files drift"
fi
st="$(yq e '.status' "$REPO/.goalspec/active/state.yaml")"
[ "$st" = "closing" ] && ok "state recoverable at closing (no hand-edit needed)" || bad "state is '$st' after failed close (expected closing)"

# Run 2: resume — self-heal: regenerate package (recompute H2), recheck passes.
if "$REPO_GS" close >/tmp/goalspec-79-run2.out 2>&1; then
  ok "resumed close self-healed drifted changed_files_hash and reached closed"
else
  cat /tmp/goalspec-79-run2.out >&2
  bad "resumed close failed"
fi
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "state closed after resume (no state.yaml hand-edit)" \
  || bad "state not closed after resume"

[ "$TESTS_FAIL" -eq 0 ]
