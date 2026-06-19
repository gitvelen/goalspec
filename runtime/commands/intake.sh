#!/usr/bin/env bash
# intake.sh — explicit intake capture lifecycle.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"

ensure_active_goal() {
  local gid cur_status
  gid="$(yq e '.active_goal_id // ""' "$state_file" 2>/dev/null || echo "")"
  cur_status="$(yq e '.status // "no_goal"' "$state_file" 2>/dev/null || echo "no_goal")"
  if [ -n "$gid" ] && [ "$gid" != "null" ] && [ "$cur_status" != "closed" ] && [ "$cur_status" != "completed" ]; then
    case "$cur_status" in
      no_goal|intake_collecting|spec_drafting|awaiting_human_confirmation) return 0 ;;
      *) echo "goalspec intake: active goal is not closed (status=$cur_status). Close or reopen it before starting another change." >&2; exit 1 ;;
    esac
  fi

  gid="$(goalspec_new_goal_id)"
  cp "$GOALSPEC_ROOT/runtime/templates/active/state.yaml" "$state_file"
  yq e -i ".active_goal_id = \"$gid\"" "$state_file"
  yq e -i ".status = \"spec_drafting\"" "$state_file"
  yq e -i ".git.base_revision = \"$(goalspec_git_head)\"" "$state_file"
  yq e -i ".git.current_revision = \"$(goalspec_git_head)\"" "$state_file"
  cp "$GOALSPEC_ROOT/runtime/templates/active/goal.md" "$GOALSPEC_ROOT/active/goal.md"
  cp "$GOALSPEC_ROOT/runtime/templates/active/intake-sources.yaml" "$GOALSPEC_ROOT/active/intake-sources.yaml"
  cp "$GOALSPEC_ROOT/runtime/templates/active/intake-conversation.md" "$GOALSPEC_ROOT/active/intake-conversation.md"
  cp "$GOALSPEC_ROOT/runtime/templates/active/intake-capture.md" "$GOALSPEC_ROOT/active/intake-capture.md"
  cp "$GOALSPEC_ROOT/runtime/templates/active/constraint-suggestions.yaml" "$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
  yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$state_file"
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
    cat > "$conv" <<EOF
# Intake Conversation

status: collecting
started_at: $(goalspec_now)

## Turn 1 - User
${*:-}
EOF
    goalspec_intake_record_conversation_source
    yq e -i ".intake_session.status = \"collecting\"" "$state_file"
    yq e -i ".intake_session.started_at = \"$(goalspec_now)\"" "$state_file"
    yq e -i ".intake_session.ended_at = null" "$state_file"
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
    {
      printf '\nended_at: %s\n' "$(goalspec_now)"
      printf '\n## Capture Instruction\n'
      printf 'Generate active/intake-capture.md and active/constraint-suggestions.yaml from this conversation and any intake sources, then ask the human to confirm the intake package before writing final goal.md or project constraints.\n'
    } >> "$conv"
    yq e -i ".intake_session.status = \"closed\"" "$state_file"
    yq e -i ".intake_session.ended_at = \"$(goalspec_now)\"" "$state_file"
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
