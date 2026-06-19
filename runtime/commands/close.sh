#!/usr/bin/env bash
# close.sh — unified V2 close gate and delivery.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"
cpf="$GOALSPEC_ROOT/active/close-package.yaml"

fail_close() {
  local msg="$1"
  yq e -i ".close.status = \"failed\" | .close.failed_at = \"$(goalspec_now)\" | .close.failure_reason = \"$msg\"" "$state_file" 2>/dev/null || true
  echo "close blocked: $msg" >&2
  echo "NEXT_USER_ACTION: Fix the blocker, regenerate the close package if it is stale, then run /goalspec close again." >&2
  exit 1
}

checkpoint() {
  local status="$1"
  yq e -i ".close.status = \"$status\" | .close.failed_at = null | .close.failure_reason = null" "$state_file"
}

state="$(yq e '.status // "no_goal"' "$state_file")"
case "$state" in
  ready_to_close)
    goalspec_state_set_status closing
    ;;
  closing)
    :
    ;;
  *)
    fail_close "state is $state, expected ready_to_close or recoverable closing"
    ;;
esac

[ -f "$cpf" ] || fail_close "close package missing"
if ! pkg_err="$(goalspec_close_validate_package_hashes 2>&1)"; then
  fail_close "$pkg_err"
fi

# Preflight outward-facing delivery requirements before mutating memory/history.
remote="$(goalspec_git_remote)"
[ -n "$remote" ] || fail_close "git remote missing"
yq e -i ".close.remote = \"$remote\"" "$state_file"
command -v gh >/dev/null 2>&1 || fail_close "gh is not installed or not on PATH"
gh auth status >/dev/null 2>&1 || fail_close "gh is not authenticated"

gate_status="$(yq e '.close.status // "not_started"' "$state_file")"
if [ "$gate_status" = "not_started" ] || [ "$gate_status" = "failed" ] || [ "$gate_status" = "verifying" ]; then
  checkpoint verifying
  if ! gate_err="$(goalspec_close_completion_gate 2>&1)"; then
    fail_close "$gate_err"
  fi
  if ! verify_err="$(goalspec_delivery_run_final_verification 2>&1)"; then
    fail_close "final verification failed: $verify_err"
  fi
  if ! secret_hits="$(goalspec_delivery_scan_secrets 2>&1)"; then
    fail_close "sensitive, large, or disallowed file detected: $secret_hits"
  fi
  if ! GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run; then
    fail_close "scope-check failed"
  fi

  vname="$(yq e '.close.history_version // ""' "$state_file")"
  if [ -z "$vname" ] || [ "$vname" = "null" ]; then
    vname="$(goalspec_close_next_history_version)"
    goalspec_close_apply_memory_patch
    goalspec_close_archive_active "$vname"
    chash="$(goalspec_contract_hash)"
    git_base="$(yq e '.git.base_revision // ""' "$state_file")"
    git_completed="$(goalspec_git_head)"
    hdir="$GOALSPEC_ROOT/history/$vname"
    changed_files="$(goalspec_git_changed_files "$git_base" | grep -v '^\.goalspec/' || true)"
    cat > "$hdir/summary.yaml" <<YML
version: $vname
goal_id: $(yq e '.active_goal_id' "$state_file")
closed_at: $(goalspec_now)
contract_hash: $chash
criteria_passed:
$(goalspec_close_required_criteria_ids | sed 's/^/  - /' | grep -v '^  - $')
git:
  base_revision: $git_base
  completed_revision: $git_completed
  dirty_at_close: $([ -n "$changed_files" ] && echo true || echo false)
changed_files:
$(echo "$changed_files" | sed 's/^/  - /' | grep -v '^  - $' || true)
YML
    yq e -i ".versions += [{\"version\": \"$vname\", \"goal_id\": \"$(yq e '.active_goal_id' "$state_file")\", \"closed_at\": \"$(goalspec_now)\", \"contract_hash\": \"$chash\", \"close_package_hash\": \"$(goalspec_close_package_hash)\"}]" "$GOALSPEC_ROOT/project/versions.yaml"
    yq e -i ".close.history_version = \"$vname\"" "$state_file"
  fi
  checkpoint completed_gate
fi

branch="$(yq e '.close.branch // ""' "$state_file")"
if [ -z "$branch" ] || [ "$branch" = "null" ]; then
  branch="$(goalspec_delivery_ensure_branch)" || fail_close "could not create or select a delivery branch"
else
  git checkout "$branch" >/dev/null 2>&1 || fail_close "could not checkout delivery branch $branch"
fi

main_commit="$(yq e '.close.main_commit // ""' "$state_file")"
if [ -z "$main_commit" ] || [ "$main_commit" = "null" ]; then
  goalspec_delivery_stage_files
  if ! goalspec_delivery_has_staged_changes; then
    fail_close "no staged changes for main commit"
  fi
  msg_file="$(mktemp)"
  yq e '.commit.message // "chore(goalspec): close goal"' "$cpf" > "$msg_file"
  git commit -F "$msg_file" >/dev/null || { rm -f "$msg_file"; fail_close "main commit failed"; }
  rm -f "$msg_file"
  main_commit="$(git rev-parse HEAD)"
  yq e -i ".close.main_commit = \"$main_commit\"" "$state_file"
  checkpoint main_committed
fi

pushed_status="$(yq e '.close.status // ""' "$state_file")"
if [ "$pushed_status" = "main_committed" ] || [ "$pushed_status" = "completed_gate" ]; then
  git push -u "$remote" "$branch" >/dev/null 2>&1 || fail_close "push failed"
  checkpoint pushed
fi

pr_url="$(yq e '.close.pr_url // ""' "$state_file")"
if [ -z "$pr_url" ] || [ "$pr_url" = "null" ]; then
  pr_url="$(goalspec_delivery_create_pr)" || fail_close "PR creation failed"
  yq e -i ".close.pr_url = \"$pr_url\"" "$state_file"
  checkpoint pr_created
fi

vname="$(yq e '.close.history_version // ""' "$state_file")"
hdir="$GOALSPEC_ROOT/history/$vname"
closed_at="$(goalspec_now)"
cat > "$hdir/delivery.yaml" <<YML
status: closed
goal_id: $(yq e '.active_goal_id' "$state_file")
history_version: $vname
branch: $branch
base_branch: $(yq e '.close.base_branch // ""' "$state_file")
remote: $remote
main_commit: $main_commit
metadata_commit: null
pr_url: $pr_url
closed_at: $closed_at
close_package_hash: $(goalspec_close_package_hash)
verification_summary: final verification passed
YML

yq e -i ".close.status = \"closed\" | .close.failed_at = null | .close.failure_reason = null" "$state_file"
goalspec_state_set_status closed

git add "$hdir/delivery.yaml" "$state_file" >/dev/null 2>&1 || fail_close "could not stage delivery metadata"
if goalspec_delivery_has_staged_changes; then
  git commit -m "chore(goalspec): record delivery metadata for $(yq e '.active_goal_id' "$state_file")" >/dev/null || fail_close "metadata commit failed"
  metadata_commit="$(git rev-parse HEAD)"
else
  metadata_commit=""
fi

git push "$remote" "$branch" >/dev/null 2>&1 || fail_close "metadata push failed"

cat <<EOF
close: $vname
  status: closed
  branch: $branch
  main_commit: $main_commit
  metadata_commit: ${metadata_commit:-null}
  pr_url: $pr_url
  history: $hdir
EOF
