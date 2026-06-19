#!/usr/bin/env bash
# compile.sh — produce / advance draft contract.yaml.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"
status="$(yq e '.status' "$state_file")"

# Blockers: must have passed intake review.
rf="$GOALSPEC_ROOT/active/reviews.yaml"
intake_pass=0
if [ -f "$rf" ]; then
  last="$(yq e '[.reviews[] | select(.kind == "intake")] | .[-1].result // ""' "$rf")"
  [ "$last" = "pass" ] && intake_pass=1
fi
if [ "$intake_pass" -ne 1 ]; then
  echo "compile blocked: intake review has not passed. Run 'goalspec review prompt intake' then apply a passing result." >&2
  exit 1
fi
goal_approvals="$(yq e '[.approvals[] | select(.kind == "goal")] | length' "$state_file" 2>/dev/null || echo 0)"
if [ "${goal_approvals:-0}" -lt 1 ]; then
  echo "compile blocked: goal not approved. Run 'goalspec approve goal'." >&2
  exit 1
fi
if goalspec_approval_stale goal; then
  echo "compile blocked: goal approval is stale vs current goal.md. Re-approve goal." >&2
  exit 1
fi

# If intake review is stale vs current goal.md, block.
if goalspec_review_stale intake; then
  echo "compile blocked: intake review is stale vs current goal.md. Re-review." >&2
  exit 1
fi

if goalspec_intake_has_sources; then
  pkg_approvals="$(yq e '[.approvals[] | select(.kind == "intake-package")] | length' "$state_file" 2>/dev/null || echo 0)"
  if [ "${pkg_approvals:-0}" -lt 1 ]; then
    echo "compile blocked: intake package not approved. Run 'goalspec approve intake-package' after reviewing intake-capture.md and constraint-suggestions.yaml." >&2
    exit 1
  fi
  if goalspec_approval_stale intake-package; then
    echo "compile blocked: intake-package approval is stale. Re-approve intake package." >&2
    exit 1
  fi
  cur_suggestions_hash="$(goalspec_constraint_suggestions_hash)"
  applied_suggestions_hash="$(yq e '.constraint_suggestions_applied_hash // ""' "$state_file" 2>/dev/null || echo "")"
  if [ -z "$applied_suggestions_hash" ] || [ "$applied_suggestions_hash" = "null" ]; then
    echo "compile blocked: constraint suggestions not applied. Run 'goalspec intake apply-suggestions'." >&2
    exit 1
  fi
  if [ "$cur_suggestions_hash" != "$applied_suggestions_hash" ]; then
    echo "compile blocked: applied constraint suggestions are stale. Re-approve package and run 'goalspec intake apply-suggestions'." >&2
    exit 1
  fi
fi

cf="$GOALSPEC_ROOT/active/contract.yaml"
if [ ! -f "$cf" ] || [ "$(yq e '.status // ""' "$cf")" = "" ]; then
  cp "$GOALSPEC_ROOT/runtime/templates/active/contract.yaml" "$cf"
fi
# Bind goal + project memory hashes into draft.
yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$cf"
yq e -i ".project_memory_hash = \"$(goalspec_project_memory_hash)\"" "$cf"
yq e -i ".status = \"draft\"" "$cf"

# Advance/confirm state: compiling is part of spec drafting (enhance.md §4).
case "$status" in
  spec_drafting) : ;;
  awaiting_human_confirmation) goalspec_state_set_status spec_drafting ;;
  *) echo "compile: unexpected state $status" >&2; exit 1 ;;
esac

cat <<EOF
draft contract written: $cf

The compiler agent should now edit $cf to fill in:
  - criteria (incl. one final: true; each may carry evidence_requirement_refs)
  - evidence_requirements
  - constraints (active project + confirmed goal + confirmed compile)
  - allowed_paths / forbidden_paths (the execution scope boundary)
  - required_regressions (from project/regression-suite.yaml)

When done: 'goalspec review prompt contract', apply a passing contract review,
then 'goalspec approve contract' and 'goalspec freeze'.
EOF
