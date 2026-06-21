#!/usr/bin/env bash
# close.sh - unified V2 close gate and delivery.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"
cpf="$GOALSPEC_ROOT/active/close-package.yaml"

fail_close() {
  local msg="$1" cur
  yq e -i ".close.status = \"failed\" | .close.failed_at = \"$(goalspec_now)\" | .close.failure_reason = \"$msg\"" "$state_file" 2>/dev/null || true
  # V2 section 8: a failed close must never remain in `closed`. If a later
  # delivery step fails after the status flip, roll back to recoverable closing.
  cur="$(yq e '.status // "no_goal"' "$state_file" 2>/dev/null || echo "no_goal")"
  if [ "$cur" = "closed" ]; then
    yq e -i '.status = "closing"' "$state_file"
  fi
  echo "close blocked: $msg" >&2
  echo "NEXT_USER_ACTION: Fix the blocker, regenerate the close package if it is stale, then run /goalspec close again." >&2
  exit 1
}

checkpoint() {
  local status="$1"
  yq e -i ".close.status = \"$status\" | .close.failed_at = null | .close.failure_reason = null" "$state_file"
}

is_resume=false
state="$(yq e '.status // "no_goal"' "$state_file")"
case "$state" in
  reopen_required)
    fail_close "state is reopen_required; review the reopen impact, revise goal.md and/or contract.yaml, then re-review, re-approve, and freeze before closing"
    ;;
  ready_to_close)
    goalspec_state_set_status closing
    ;;
  closing)
    # Resuming an interrupted close. The close package was already hash-validated
    # before close's own side effects ran, so skip package hash validation here.
    is_resume=true
    ;;
  running)
    if gate_err="$(goalspec_close_completion_gate 2>&1)"; then
      fail_close "close package is not generated yet; run /goalspec run to generate it before /goalspec close"
    else
      fail_close "close package is not ready; /goalspec run must pass completion gate first: $gate_err"
    fi
    ;;
  *)
    fail_close "state is $state, expected ready_to_close or recoverable closing"
    ;;
esac

[ -f "$cpf" ] || fail_close "close package missing"
if [ "$is_resume" != "true" ]; then
  if ! pkg_err="$(goalspec_close_validate_package_hashes 2>&1)"; then
    fail_close "$pkg_err"
  fi
fi

delivery_mode="$(goalspec_delivery_mode)"
case "$delivery_mode" in
  github_pr|push_only|local_commit|archive_only) ;;
  invalid:*) fail_close "invalid delivery.mode ${delivery_mode#invalid:}; expected github_pr, push_only, local_commit, or archive_only" ;;
esac
yq e -i ".close.delivery_mode = \"$delivery_mode\"" "$state_file"

remote=""
case "$delivery_mode" in
  github_pr|push_only)
    remote="$(goalspec_git_remote)"
    [ -n "$remote" ] || fail_close "git remote missing"
    yq e -i ".close.remote = \"$remote\"" "$state_file"
    ;;
  local_commit|archive_only)
    yq e -i ".close.remote = null" "$state_file"
    ;;
esac

if [ "$delivery_mode" = "github_pr" ]; then
  command -v gh >/dev/null 2>&1 || fail_close "gh is not installed or not on PATH"
  gh auth status >/dev/null 2>&1 || fail_close "gh is not authenticated"
fi

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
main_commit="$(yq e '.close.main_commit // ""' "$state_file")"
pr_url="$(yq e '.close.pr_url // ""' "$state_file")"

if [ "$delivery_mode" != "archive_only" ]; then
  if [ -z "$branch" ] || [ "$branch" = "null" ]; then
    branch="$(goalspec_delivery_ensure_branch)" || fail_close "could not create or select a delivery branch"
  else
    git -C "$PROJECT_ROOT" checkout "$branch" >/dev/null 2>&1 || fail_close "could not checkout delivery branch $branch"
  fi

  if [ -z "$main_commit" ] || [ "$main_commit" = "null" ]; then
    goalspec_delivery_stage_files
    if ! goalspec_delivery_has_staged_changes; then
      fail_close "no staged changes for main commit"
    fi
    msg_file="$(mktemp)"
    yq e '.commit.message // "chore(goalspec): close goal"' "$cpf" > "$msg_file"
    git -C "$PROJECT_ROOT" commit -F "$msg_file" >/dev/null || { rm -f "$msg_file"; fail_close "main commit failed"; }
    rm -f "$msg_file"
    main_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    yq e -i ".close.main_commit = \"$main_commit\"" "$state_file"
    checkpoint main_committed
  fi

  pushed_status="$(yq e '.close.status // ""' "$state_file")"
  if [ "$delivery_mode" = "github_pr" ] || [ "$delivery_mode" = "push_only" ]; then
    if [ "$pushed_status" = "main_committed" ] || [ "$pushed_status" = "completed_gate" ]; then
      git -C "$PROJECT_ROOT" push "$remote" "$main_commit:refs/heads/$branch" >/dev/null 2>&1 || fail_close "main branch push failed"
      checkpoint pushed
    fi
  fi

  if [ "$delivery_mode" = "github_pr" ]; then
    if [ -z "$pr_url" ] || [ "$pr_url" = "null" ]; then
      pr_url="$(goalspec_delivery_create_pr)" || fail_close "PR creation failed"
      yq e -i ".close.pr_url = \"$pr_url\"" "$state_file"
      checkpoint pr_created
    fi
  else
    pr_url=""
    yq e -i ".close.pr_url = null" "$state_file"
  fi
else
  branch=""
  main_commit=""
  pr_url=""
  yq e -i '.close.branch = null | .close.base_branch = null | .close.main_commit = null | .close.pr_url = null' "$state_file"
fi

vname="$(yq e '.close.history_version // ""' "$state_file")"
hdir="$GOALSPEC_ROOT/history/$vname"
closed_at="$(goalspec_now)"
prev_meta="$(yq e '.close.metadata_commit // ""' "$state_file")"
[ "$prev_meta" = "null" ] && prev_meta=""
cat > "$hdir/delivery.yaml" <<YML
status: closed
goal_id: $(yq e '.active_goal_id' "$state_file")
history_version: $vname
delivery_mode: $delivery_mode
branch: ${branch:-null}
base_branch: $(yq e '.close.base_branch // ""' "$state_file")
remote: ${remote:-null}
main_commit: ${main_commit:-null}
metadata_commit: ${prev_meta:-null}
pr_url: ${pr_url:-null}
closed_at: $closed_at
close_package_hash: $(goalspec_close_package_hash)
verification_summary: final verification passed
YML

# Flip the top-level status to closed BEFORE the metadata commit so the commit
# carries the final state and the working tree is clean on success. fail_close
# rolls this back if a later step fails (V2 section 8).
yq e -i ".close.status = \"closed\" | .close.failed_at = null | .close.failure_reason = null" "$state_file"
goalspec_state_set_status closed
# Reset the run-loop stop-loss counter: a closed change is done, and the next
# /goalspec start begins a fresh loop from zero.
yq e -i '.run_loop.iteration = 0 | .run_loop.last_outcome = null | .run_loop.last_at = null | .run_loop.stall_count = 0 | .run_loop.last_fingerprint = null | .run_loop.last_evidence_hash = null | .run_loop.trajectory = {"tried_paths": [], "failed_approaches": [], "current_blocker": "", "next_step": ""}' "$state_file"

if [ "$delivery_mode" = "archive_only" ]; then
  cat <<EOF
close: $vname
  status: closed
  delivery_mode: $delivery_mode
  history: $hdir
EOF
  exit 0
fi

git -C "$PROJECT_ROOT" add "$hdir/delivery.yaml" "$state_file" >/dev/null 2>&1 || fail_close "could not stage delivery metadata"
if [ -z "$prev_meta" ]; then
  goalspec_delivery_has_staged_changes || fail_close "no staged changes for metadata commit"
  git -C "$PROJECT_ROOT" commit -m "chore(goalspec): record delivery metadata for $(yq e '.active_goal_id' "$state_file")" >/dev/null || fail_close "metadata commit failed"
  metadata_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  yq e -i ".close.metadata_commit = \"$metadata_commit\"" "$state_file"
else
  metadata_commit="$prev_meta"
  if goalspec_delivery_has_staged_changes; then
    git -C "$PROJECT_ROOT" commit --amend --no-edit >/dev/null 2>&1 || fail_close "metadata commit amend failed"
    metadata_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    yq e -i ".close.metadata_commit = \"$metadata_commit\"" "$state_file"
  fi
fi

if [ "$delivery_mode" = "github_pr" ] || [ "$delivery_mode" = "push_only" ]; then
  git -C "$PROJECT_ROOT" push "$remote" "$branch" >/dev/null 2>&1 || fail_close "metadata push failed"
fi

cat <<EOF
close: $vname
  status: closed
  delivery_mode: $delivery_mode
  branch: $branch
  main_commit: $main_commit
  metadata_commit: ${metadata_commit:-null}
  pr_url: ${pr_url:-null}
  history: $hdir
EOF
