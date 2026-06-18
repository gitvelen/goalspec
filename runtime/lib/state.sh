#!/usr/bin/env bash
# state.sh — state.yaml read/write and transition validation.

# Allowed state transitions. Returns 0 if allowed.
goalspec_state_valid_transition() {
  local from="$1" to="$2"
  case "$from:$to" in
    draft:intake_reviewed|\
    intake_reviewed:contract_draft|\
    contract_draft:contract_reviewed|\
    contract_reviewed:compiled|\
    contract_reviewed:prompt_ready|\
    compiled:running|\
    prompt_ready:running|\
    running:compiled|\
    running:prompt_ready|\
    compiled:completed|\
    prompt_ready:completed|\
    running:completed|\
    *:blocked|\
    *:reopen_required|\
    blocked:draft|\
    blocked:intake_reviewed|\
    blocked:contract_reviewed|\
    reopen_required:draft|\
    reopen_required:intake_reviewed) return 0 ;;
    *) return 1 ;;
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
