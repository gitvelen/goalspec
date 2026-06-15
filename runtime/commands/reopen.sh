#!/usr/bin/env bash
# reopen.sh — make old contract/evidence/verdict stale.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

reason="${1:-manual reopen}"
state_file="$GOALSPEC_ROOT/active/state.yaml"

# Mark reopen.
yq e -i ".reopen_reason = \"$reason\"" "$state_file"
# Force contract/evidence/verdict stale by clearing their recorded hashes.
# (so any next/judge/complete sees staleness)
yq e -i ".contract_hash = \"\"" "$state_file"
yq e -i ".evidence_hash = \"\"" "$state_file"
# Reset current_work_unit and bump state to reopen_required (transition allowed).
cur="$(yq e '.status' "$state_file")"
case "$cur" in
  reopen_required) : ;;
  *) goalspec_state_set_status reopen_required ;;
esac
echo "reopened: $reason"
echo "next: edit goal.md or contract.yaml, then re-review/approve/freeze"
