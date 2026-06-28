#!/usr/bin/env bash
# intake.sh — explicit intake capture lifecycle.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"

ensure_active_goal() {
  goalspec_assert_can_start || exit 1
  if ! goalspec_git_worktree_clean; then
    echo "start blocked: business worktree has uncommitted changes relative to HEAD." >&2
    echo "  intake snapshots source files into .goalspec/artifacts/intake/ at 'source' time," >&2
    echo "  so a dirty worktree corrupts intake provenance — freeze cannot catch this" >&2
    echo "  (the dirty snapshot is frozen before freeze runs). Commit or stash first." >&2
    echo "NEXT_USER_ACTION: commit or stash business changes, then run 'goalspec start' again." >&2
    exit 1
  fi
  goalspec_reset_active_workspace
}

sub="${1:-}"; shift || true
case "$sub" in
  begin)
    ensure_active_goal
    cur="$(yq e '.intake_session.status // "not_started"' "$state_file")"
    if [ "$cur" = "collecting" ]; then
      echo "goalspec intake begin: already collecting" >&2
      exit 1
    fi
    mkdir -p "$GOALSPEC_ROOT/artifacts/intake"
    conv="$GOALSPEC_ROOT/active/intake-conversation.md"
    started_at="$(goalspec_now)"
    yq e -i ".intake_session.status = \"collecting\"" "$state_file"
    yq e -i ".intake_session.started_at = \"$started_at\"" "$state_file"
    yq e -i ".intake_session.ended_at = null" "$state_file"
    goalspec_transcript_bind_current >/dev/null 2>&1 || true
    cat > "$conv" <<EOF
# Intake Conversation

started_at: $started_at

## Turn 1 - User
${*:-}
EOF
    goalspec_intake_record_conversation_source
    goalspec_state_set_status intake_collecting
    echo "intake collecting: $conv"
    echo "next: append begin/end conversation turns to active/intake-conversation.md; then run 'goalspec intake end'"
    ;;
  add-source)
    [ $# -ge 1 ] || { echo "usage: goalspec intake add-source <path>" >&2; exit 2; }
    # Sources may only join an OPEN intake window. Do not auto-create a goal or
    # accept material once the window is closed — both bypass the formal
    # start/end intent boundary (see goalspec_enhance.md §9, §17).
    [ -f "$state_file" ] || { echo "goalspec intake add-source: no active goal. Run 'goalspec start' to open an intake window first." >&2; exit 1; }
    cur="$(yq e '.intake_session.status // "not_started"' "$state_file")"
    [ "$cur" = "collecting" ] || { echo "goalspec intake add-source: intake window is not open (status=$cur). Run 'goalspec start' first; '/goalspec end' closes the window." >&2; exit 1; }
    for src in "$@"; do
      goalspec_intake_add_source "$src"
      echo "source added: $src"
    done
    ;;
  end)
    [ -f "$state_file" ] || { echo "goalspec intake end: no active goal" >&2; exit 1; }
    cur="$(yq e '.intake_session.status // "not_started"' "$state_file")"
    [ "$cur" = "collecting" ] || { echo "goalspec intake end: intake is not collecting (status=$cur)" >&2; exit 1; }
    conv="$GOALSPEC_ROOT/active/intake-conversation.md"
    started_at="$(yq e '.intake_session.started_at // ""' "$state_file")"
    ended_at="$(goalspec_now)"
    # Mechanically rebuild the conversation log from the AI session transcript.
    # On failure, fall back to appending the boundary + Capture Instruction to
    # the begin skeleton so end is never blocked by a transcript problem.
    if [ -n "$started_at" ] && goalspec_transcript_rebuild "$started_at" "$ended_at"; then
      : # rebuild rewrote conversation.md with the full sliced window
    else
      {
        printf '\nended_at: %s\n' "$ended_at"
        printf '\n## Capture Instruction\n'
        printf 'Generate active/intake-capture.md and active/constraint-suggestions.yaml from this conversation and any intake sources, then ask the human to confirm the intake package before writing final goal.md or project constraints.\n'
      } >> "$conv"
      echo "goalspec intake end: warning - conversation not rebuilt from transcript; active/intake-conversation.md retains the begin skeleton." >&2
    fi
    yq e -i ".intake_session.status = \"closed\"" "$state_file"
    yq e -i ".intake_session.ended_at = \"${ended_at}\"" "$state_file"
    goalspec_state_set_status spec_drafting
    echo "intake collection closed"
    echo "DRAFT_FOR_HUMAN_REVIEW_REQUIRED:"
    echo "  - Goal"
    echo "  - Criteria"
    echo "  - Constraints"
    echo "  - Out of Scope"
    echo "  - Blocking Questions"
    echo "next_user_action: draft these from active/intake-capture.md, active/constraint-suggestions.yaml, active/intake-conversation.md, and active/intake-sources.yaml; then ask the human to confirm or modify."
    ;;
  apply-suggestions)
    [ -f "$state_file" ] || { echo "goalspec intake apply-suggestions: no active goal" >&2; exit 1; }
    if ! yq e '[.approvals[] | select(.kind == "intake-package")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
      echo "intake apply-suggestions blocked: intake package not approved. Run 'goalspec approve intake-package'." >&2
      exit 1
    fi
    if goalspec_approval_stale intake-package; then
      echo "intake apply-suggestions blocked: intake-package approval is stale. Re-approve intake package." >&2
      exit 1
    fi
    goalspec_intake_apply_constraint_suggestions
    echo "constraint suggestions applied"
    ;;
  *)
    echo "usage: goalspec intake <begin [text]|add-source <path>|end|apply-suggestions>" >&2
    exit 2
    ;;
esac
