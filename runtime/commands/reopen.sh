#!/usr/bin/env bash
# reopen.sh — mark the current goal/contract basis for re-review (reopen_required).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

reason="${1:-manual reopen}"
state_file="$GOALSPEC_ROOT/active/state.yaml"

# Mark reopen.
yq e -i ".reopen_reason = \"$reason\"" "$state_file"
# Record the reopen reason, clear the recorded contract/evidence hashes (the
# old basis is no longer current), and move state to reopen_required.
# NOTE: this does NOT itself block next/judge/complete — an empty recorded hash
# reads as "not stale", and those commands have no reopen_required status gate.
# The human must edit goal/contract and re-review/approve/freeze to rebuild the
# basis before execution should resume.
yq e -i ".contract_hash = \"\"" "$state_file"
yq e -i ".evidence_hash = \"\"" "$state_file"
# Move state to reopen_required (transition allowed from anywhere).
cur="$(yq e '.status' "$state_file")"
case "$cur" in
  reopen_required) : ;;
  *) goalspec_state_set_status reopen_required ;;
esac
echo "reopened: $reason"
echo "next: edit goal.md or contract.yaml, then re-review/approve/freeze"
