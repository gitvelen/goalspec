#!/usr/bin/env bash
# stale.sh — staleness detection based on hash comparisons.
#
# Three independent sources of staleness (GOALSPEC §26.3):
#  - goal.md change  -> stale intake review, goal approval, contract review,
#                       contract approval, frozen contract
#  - contract change -> stale evidence, verdict, complete basis
#  - evidence change -> stale verdicts referencing the old evidence hash
#  - memory-patch change -> stale memory-patch approval

goalspec_stale_goal_changed() {
  local cur cur_rec
  cur="$(goalspec_goal_hash)"
  cur_rec="$(goalspec_state_get '.goal_hash // ""')"
  [ -n "$cur_rec" ] && [ "$cur" != "$cur_rec" ]
}

goalspec_stale_contract_changed() {
  local cur cur_rec
  cur="$(goalspec_contract_hash)"
  cur_rec="$(goalspec_state_get '.contract_hash // ""')"
  [ -n "$cur_rec" ] && [ "$cur" != "$cur_rec" ]
}

goalspec_stale_evidence_changed() {
  local cur cur_rec
  cur="$(goalspec_evidence_hash)"
  cur_rec="$(goalspec_state_get '.evidence_hash // ""')"
  [ -n "$cur_rec" ] && [ "$cur" != "$cur_rec" ]
}

goalspec_stale_memory_patch_changed() {
  local cur cur_rec
  cur="$(goalspec_memory_patch_hash)"
  cur_rec="$(goalspec_state_get '.memory_patch_hash // ""')"
  [ -n "$cur_rec" ] && [ "$cur" != "$cur_rec" ]
}

# Returns 0 (true) if a stored review of given kind is stale.
# kinds: intake, contract, criteria
goalspec_review_stale() {
  local kind="$1"
  local rf="$GOALSPEC_ROOT/active/reviews.yaml"
  [ -f "$rf" ] || return 0
  local target_hash
  target_hash="$(yq e ".reviews[] | select(.kind == \"$kind\") | .target_hash // \"\"" "$rf" | tail -1)"
  [ -z "$target_hash" ] && return 0
  local cur
  if [ "$kind" = "intake" ]; then
    cur="$(goalspec_goal_hash)"
  else
    cur="$(goalspec_contract_hash)"
  fi
  [ "$target_hash" != "$cur" ]
}

# 0 if approval of kind is stale (target hash differs from current).
goalspec_approval_stale() {
  local kind="$1"
  local sf="$GOALSPEC_ROOT/active/state.yaml"
  local target_hash
  target_hash="$(yq e ".approvals[] | select(.kind == \"$kind\") | .target_hash // \"\"" "$sf" | tail -1)"
  [ -z "$target_hash" ] && return 0
  local cur
  case "$kind" in
    goal) cur="$(goalspec_goal_hash)" ;;
    contract) cur="$(goalspec_contract_hash)" ;;
    memory-patch) cur="$(goalspec_memory_patch_hash)" ;;
    high-risk) return 1 ;; # bound to action id not content hash
    regression-waiver) return 1 ;;
    *) return 0 ;;
  esac
  [ "$target_hash" != "$cur" ]
}

# Aggregate list of stale blockers as newline string. Empty = none.
goalspec_stale_blockers() {
  local out=""
  if goalspec_stale_goal_changed; then
    out="${out}goal_changed "
  fi
  if goalspec_stale_contract_changed; then
    out="${out}contract_changed "
  fi
  if goalspec_stale_evidence_changed; then
    out="${out}evidence_changed "
  fi
  if goalspec_stale_memory_patch_changed; then
    out="${out}memory_patch_changed "
  fi
  echo "$out"
}
