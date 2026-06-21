#!/usr/bin/env bash
# state.sh — state.yaml read/write and transition validation.

# Allowed state transitions (enhance_v2.md §4 lifecycle). Returns 0 if allowed.
# States: no_goal -> intake_collecting -> spec_drafting ->
# awaiting_human_confirmation -> ready_to_run -> running -> ready_to_close ->
# closing -> closed. blocked / reopen_required are recovery extensions reachable
# from anywhere. frozen_ready / prompt_ready are accepted as ready_to_run aliases
# for the freeze -> run handoff.
goalspec_state_valid_transition() {
  local from="$1" to="$2"
  case "$from:$to" in
    no_goal:intake_collecting|\
    no_goal:spec_drafting|\
    closed:intake_collecting|\
    closed:spec_drafting|\
    intake_collecting:spec_drafting|\
    spec_drafting:awaiting_human_confirmation|\
    spec_drafting:intake_collecting|\
    awaiting_human_confirmation:ready_to_run|\
    ready_to_run:running|\
    ready_to_run:ready_to_close|\
    ready_to_run:awaiting_human_confirmation|\
    running:ready_to_close|\
    running:ready_to_run|\
    ready_to_close:closing|\
    ready_to_close:running|\
    closing:closed|\
    closing:ready_to_close|\
    closing:closing|\
    closed:closed|\
    no_goal:ready_to_run|\
    awaiting_human_confirmation:frozen_ready|\
    awaiting_human_confirmation:prompt_ready|\
    frozen_ready:prompt_ready|\
    frozen_ready:ready_to_run|\
    frozen_ready:awaiting_human_confirmation|\
    prompt_ready:running|\
    prompt_ready:ready_to_run|\
    prompt_ready:awaiting_human_confirmation|\
    prompt_ready:ready_to_close|\
    running:prompt_ready|\
    *:blocked|\
    *:reopen_required|\
    blocked:no_goal|\
    blocked:spec_drafting|\
    blocked:awaiting_human_confirmation|\
    blocked:ready_to_close|\
    blocked:closing|\
    reopen_required:no_goal|\
    reopen_required:spec_drafting|\
    reopen_required:awaiting_human_confirmation|\
    reopen_required:ready_to_run) return 0 ;;
    *) return 1 ;;
  esac
}

# V2 §11 / §10: a new goal may begin only from no_goal or closed. Any other
# status means an active change is in flight and must be closed (or reopened)
# first — it must never be silently overwritten. Returns 0 if a new goal may
# start, 1 (with a user-facing message) otherwise.
goalspec_assert_can_start() {
  local state_file="$GOALSPEC_ROOT/active/state.yaml" cur
  [ -f "$state_file" ] || return 0
  cur="$(yq e '.status // "no_goal"' "$state_file" 2>/dev/null || echo "no_goal")"
  case "$cur" in
    no_goal|closed) return 0 ;;
    *) echo "goalspec: another goal is active (status=$cur). Run /goalspec close to close it, or /goalspec reopen <reason> if its spec is wrong." >&2; return 1 ;;
  esac
}

goalspec_state_get() {
  local file="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$file" ] || { echo ""; return 1; }
  yq e ".$1" "$file"
}

goalspec_state_set_status() {
  local new_status="$1"
  local file="$GOALSPEC_ROOT/active/state.yaml"
  local current
  current="$(yq e '.status' "$file")"
  if [ "$current" != "$new_status" ]; then
    if ! goalspec_state_valid_transition "$current" "$new_status"; then
      goalspec_die "invalid state transition: $current -> $new_status"
    fi
  fi
  yq e -i ".status = \"$new_status\"" "$file"
}

goalspec_state_set() {
  # set a single field
  local key="$1" val="$2"
  local file="$GOALSPEC_ROOT/active/state.yaml"
  yq e -i ".${key} = \"${val}\"" "$file"
}
