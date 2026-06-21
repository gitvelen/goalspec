#!/usr/bin/env bash
# reopen.sh — mark the current goal/contract basis for re-review (reopen_required).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

reason="${1:-manual reopen}"
state_file="$GOALSPEC_ROOT/active/state.yaml"
impact_file="$GOALSPEC_ROOT/active/reopen-impact.yaml"
prev_contract_hash="$(goalspec_state_get 'contract_hash' 2>/dev/null || echo '')"
prev_evidence_hash="$(goalspec_state_get 'evidence_hash' 2>/dev/null || echo '')"
prev_goal_hash="$(goalspec_state_get 'goal_hash' 2>/dev/null || echo '')"
prev_criteria_hash="$(goalspec_state_get 'criteria_hash' 2>/dev/null || echo '')"
prev_constraints_hash="$(goalspec_state_get 'constraints_hash' 2>/dev/null || echo '')"

# Mark reopen.
yq e -i ".reopen_reason = \"$reason\"" "$state_file"
yq e -i ".reopen_impact_hash = null" "$state_file"
# Record the reopen reason, clear the recorded contract/evidence hashes (the
# old basis is no longer current), demote the frozen contract back to draft, and
# move state to reopen_required. Execution may resume only after re-review,
# re-approval, and re-freeze rebuild the basis.
yq e -i ".contract_hash = \"\"" "$state_file"
yq e -i ".evidence_hash = \"\"" "$state_file"
# Reset the run-loop stop-loss counter: the execution basis is demoted back to
# draft, so the next /goalspec run after re-freeze starts a fresh loop.
yq e -i '.run_loop.iteration = 0 | .run_loop.last_outcome = null | .run_loop.last_at = null | .run_loop.stall_count = 0 | .run_loop.last_fingerprint = null | .run_loop.last_evidence_hash = null | .run_loop.trajectory = {"tried_paths": [], "failed_approaches": [], "current_blocker": "", "next_step": ""}' "$state_file"
[ -f "$GOALSPEC_ROOT/active/contract.yaml" ] && yq e -i '.status = "draft" | del(.contract_hash)' "$GOALSPEC_ROOT/active/contract.yaml"

cp "$GOALSPEC_ROOT/runtime/templates/active/reopen-impact.yaml" "$impact_file"
yq e -i ".reopen_reason = \"$reason\"" "$impact_file"
yq e -i ".contract_hash_before_reopen = \"$prev_contract_hash\"" "$impact_file"
yq e -i ".evidence_hash_before_reopen = \"$prev_evidence_hash\"" "$impact_file"
yq e -i ".goal_hash_before_reopen = \"$prev_goal_hash\"" "$impact_file"
yq e -i ".criteria_hash_before_reopen = \"$prev_criteria_hash\"" "$impact_file"
yq e -i ".constraints_hash_before_reopen = \"$prev_constraints_hash\"" "$impact_file"
yq e -i '.status = "required"' "$impact_file"
# Move state to reopen_required (transition allowed from anywhere).
cur="$(yq e '.status' "$state_file")"
case "$cur" in
  reopen_required) : ;;
  *) goalspec_state_set_status reopen_required ;;
esac
echo "reopened: $reason"
echo "reopen impact template: .goalspec/active/reopen-impact.yaml"
echo "next: complete reopen-impact.yaml, mark reviewed_by_human=true, revise goal.md and/or contract.yaml, then re-review, re-approve, and freeze before /goalspec run"
