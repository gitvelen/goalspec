#!/usr/bin/env bash
# GOALC #40: close performs configured git delivery and records metadata.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Default github_pr mode preserves the original remote + gh + PR behavior.
fresh_initialized_repo goalc-40-github
install_fake_gh
setup_test_remote
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true
prepare_ready_to_close

if "$REPO_GS" close >/tmp/goalspec-close40-github.out 2>&1; then
  ok "github_pr close succeeds with fake gh and remote"
else
  cat /tmp/goalspec-close40-github.out >&2
  bad "github_pr close failed"
fi

[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] && ok "github_pr state is closed" || bad "github_pr state not closed"
[ -f "$REPO/.goalspec/history/v0001/delivery.yaml" ] && ok "github_pr delivery metadata written" || bad "github_pr delivery metadata missing"
[ "$(yq e '.delivery_mode' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "github_pr" ] && ok "github_pr mode recorded" || bad "github_pr mode not recorded"
[ "$(yq e '.pr_url' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "https://example.test/org/repo/pull/1" ] && ok "PR URL recorded" || bad "PR URL not recorded"
[ -n "$(yq e '.close.main_commit // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "github_pr main commit recorded" || bad "github_pr main commit missing"
[ -n "$(yq e '.close.branch // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "github_pr branch recorded" || bad "github_pr branch missing"

# push_only commits and pushes but skips PR creation and gh dependency.
fresh_initialized_repo goalc-40-push-only
setup_test_remote
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true
yq e -i '.delivery.mode = "push_only"' "$REPO/.goalspec/project/profile.yaml"
prepare_ready_to_close

if "$REPO_GS" close >/tmp/goalspec-close40-push.out 2>&1; then
  ok "push_only close succeeds without PR"
else
  cat /tmp/goalspec-close40-push.out >&2
  bad "push_only close failed"
fi
[ "$(yq e '.delivery_mode' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "push_only" ] && ok "push_only mode recorded" || bad "push_only mode not recorded"
[ "$(yq e '.pr_url' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "null" ] && ok "push_only skips PR URL" || bad "push_only unexpectedly recorded PR URL"
[ -n "$(yq e '.close.metadata_commit // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "push_only metadata commit recorded" || bad "push_only metadata commit missing"

# local_commit should not require a remote or gh.
fresh_initialized_repo goalc-40-local
yq e -i '.delivery.mode = "local_commit"' "$REPO/.goalspec/project/profile.yaml"
prepare_ready_to_close

if "$REPO_GS" close >/tmp/goalspec-close40-local.out 2>&1; then
  ok "local_commit close succeeds without remote or gh"
else
  cat /tmp/goalspec-close40-local.out >&2
  bad "local_commit close failed"
fi
[ "$(yq e '.delivery_mode' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "local_commit" ] && ok "local_commit mode recorded" || bad "local_commit mode not recorded"
[ "$(yq e '.remote' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "null" ] && ok "local_commit has no remote" || bad "local_commit unexpectedly recorded remote"
[ -n "$(yq e '.close.metadata_commit // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "local_commit metadata commit recorded" || bad "local_commit metadata commit missing"

# archive_only closes history/state without git delivery commits, remote, or gh.
fresh_initialized_repo goalc-40-archive
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
prepare_ready_to_close
pre_head="$(git -C "$REPO" rev-parse HEAD)"

if "$REPO_GS" close >/tmp/goalspec-close40-archive.out 2>&1; then
  ok "archive_only close succeeds without remote or gh"
else
  cat /tmp/goalspec-close40-archive.out >&2
  bad "archive_only close failed"
fi
post_head="$(git -C "$REPO" rev-parse HEAD)"
[ "$post_head" = "$pre_head" ] && ok "archive_only does not create git commits" || bad "archive_only changed git HEAD"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] && ok "archive_only state is closed" || bad "archive_only state not closed"
[ "$(yq e '.delivery_mode' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "archive_only" ] && ok "archive_only mode recorded" || bad "archive_only mode not recorded"
[ "$(yq e '.main_commit' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "null" ] && ok "archive_only has no main commit" || bad "archive_only unexpectedly recorded main commit"

[ "$TESTS_FAIL" -eq 0 ]
