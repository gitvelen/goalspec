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
if goalspec_approval_stale goal || ! yq e '.approvals[] | select(.kind == "goal")' "$state_file" >/dev/null 2>&1; then
  if ! yq e '[.approvals[] | select(.kind == "goal")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
    echo "compile blocked: goal not approved. Run 'goalspec approve goal'." >&2
    exit 1
  fi
fi

# If intake review is stale vs current goal.md, block.
if goalspec_review_stale intake; then
  echo "compile blocked: intake review is stale vs current goal.md. Re-review." >&2
  exit 1
fi

cf="$GOALSPEC_ROOT/active/contract.yaml"
if [ ! -f "$cf" ] || [ "$(yq e '.status // ""' "$cf")" = "" ]; then
  cp "$GOALSPEC_ROOT/runtime/templates/active/contract.yaml" "$cf"
fi
# Bind goal + project memory hashes into draft.
yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$cf"
yq e -i ".project_memory_hash = \"$(goalspec_project_memory_hash)\"" "$cf"
yq e -i ".status = \"draft\"" "$cf"

# Advance state if appropriate.
case "$status" in
  intake_reviewed) goalspec_state_set_status contract_draft ;;
  contract_draft) : ;;
  *) echo "compile: unexpected state $status" >&2; exit 1 ;;
esac

cat <<EOF
draft contract written: $cf

The compiler agent should now edit $cf to fill in:
  - criteria (incl. one final: true)
  - work_units (behavior slices, each with criteria_refs, allowed_paths,
    forbidden_paths, evidence_requirement_refs)
  - coverage_map (every core goal scenario + must_not_happen)
  - evidence_requirements
  - constraints (active project + confirmed goal + confirmed compile)
  - required_regressions (from project/regression-suite.yaml)

When done: 'goalspec review prompt contract', apply a passing contract review,
then 'goalspec approve contract' and 'goalspec freeze'.
EOF
