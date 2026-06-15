#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

mode="text"
if [ "${1:-}" = "--json" ]; then mode="json"; fi

STATE="(no active goal)"
NEXT_ACTION="Run: goalspec new-goal"
ROLE="intake"
READ=".goalspec/ai/core.md, .goalspec/ai/intake.md"
MAY_EDIT=".goalspec/active/goal.md, .goalspec/active/questions.yaml"
MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/project/**"
BLOCKERS=""
CWU="(none)"
CC="All required criteria pass; final criteria pass; no blockers; scope-check pass; memory-patch approved."

state_file="$GOALSPEC_ROOT/active/state.yaml"
if [ -f "$state_file" ]; then
  STATE="$(yq e '.status' "$state_file")"
  CWU="$(yq e '.current_work_unit // "(none)"' "$state_file")"
fi

# Derive NEXT_ACTION / ROLE / boundaries from state.
case "$STATE" in
  draft)
    NEXT_ACTION="Write active/goal.md (intake agent), then: goalspec review prompt intake -> goalspec review apply"
    ROLE="intake"
    READ=".goalspec/ai/core.md, .goalspec/ai/intake.md, .goalspec/active/goal.md"
    MAY_EDIT=".goalspec/active/goal.md, .goalspec/active/questions.yaml"
    MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/project/**"
    ;;
  intake_reviewed)
    NEXT_ACTION="Compile draft contract: goalspec compile"
    ROLE="compiler"
    READ=".goalspec/ai/core.md, .goalspec/ai/compiler.md, .goalspec/active/goal.md, .goalspec/project/*.yaml"
    MAY_EDIT=".goalspec/active/contract.yaml (status=draft), .goalspec/active/questions.yaml"
    MUST_NOT_EDIT=".goalspec/active/goal.md, .goalspec/active/verdict.yaml, business code"
    ;;
  contract_draft)
    NEXT_ACTION="Review contract: goalspec review prompt contract, then goalspec review apply"
    ROLE="compiler"
    READ=".goalspec/ai/core.md, .goalspec/ai/compiler.md, .goalspec/active/contract.yaml"
    MAY_EDIT=".goalspec/active/contract.yaml (status=draft), .goalspec/active/questions.yaml"
    MUST_NOT_EDIT=".goalspec/active/goal.md, .goalspec/active/verdict.yaml, business code"
    ;;
  contract_reviewed)
    NEXT_ACTION="Approve and freeze contract: goalspec approve contract && goalspec freeze"
    ROLE="human"
    READ=".goalspec/active/contract.yaml, .goalspec/active/goal.md"
    MAY_EDIT="(nothing)"
    MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/goal.md, business code"
    ;;
  compiled)
    NEXT_ACTION="Pick a work unit: goalspec next"
    ROLE="executor"
    READ=".goalspec/ai/core.md, .goalspec/ai/executor.md, .goalspec/active/contract.yaml"
    MAY_EDIT="business code within WU allowed_paths, .goalspec/active/trace.yaml, .goalspec/active/evidence.yaml, .goalspec/artifacts/**"
    MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/active/goal.md, .goalspec/project/**, .goalspec/history/**"
    ;;
  running)
    NEXT_ACTION="Produce evidence, then: goalspec judge prompt <wu> -> goalspec judge apply <file>"
    ROLE="guardian"
    READ=".goalspec/ai/core.md, .goalspec/ai/guardian.md, .goalspec/active/contract.yaml, .goalspec/active/evidence.yaml, .goalspec/active/trace.yaml"
    MAY_EDIT=".goalspec/active/verdict.yaml, .goalspec/active/reviews.yaml, .goalspec/active/regressions.yaml, .goalspec/active/memory-patch.yaml"
    MUST_NOT_EDIT="business code, .goalspec/active/contract.yaml, .goalspec/active/goal.md, .goalspec/project/**"
    ;;
  completed)
    NEXT_ACTION="Goal completed. To start another: goalspec new-goal"
    ROLE="(none)"
    READ=".goalspec/project/versions.yaml"
    MAY_EDIT="(nothing)"
    MUST_NOT_EDIT=".goalspec/history/**"
    ;;
  blocked)
    NEXT_ACTION="Resolve blocker or reopen: goalspec reopen"
    ROLE="intake"
    READ=".goalspec/active/state.yaml, .goalspec/active/questions.yaml"
    MAY_EDIT=".goalspec/active/goal.md, .goalspec/active/questions.yaml"
    MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/verdict.yaml"
    ;;
  reopen_required)
    NEXT_ACTION="Reopen: goalspec reopen"
    ROLE="intake"
    READ=".goalspec/active/state.yaml"
    MAY_EDIT=".goalspec/active/goal.md"
    MUST_NOT_EDIT=".goalspec/active/contract.yaml (frozen), .goalspec/active/verdict.yaml"
    ;;
esac

# Add stale warnings to blockers.
sb="$(goalspec_stale_blockers)"
if [ -n "$sb" ]; then
  BLOCKERS="${BLOCKERS}stale: ${sb}"
fi

if [ "$mode" = "json" ]; then
  yq -o=json -I=0 '.' <<EOF
state: "$STATE"
next_action: "$NEXT_ACTION"
role: "$ROLE"
read: "$READ"
may_edit: "$MAY_EDIT"
must_not_edit: "$MUST_NOT_EDIT"
blockers: "${BLOCKERS}"
current_work_unit: "${CWU}"
completion_condition: "${CC}"
EOF
  exit 0
fi

cat <<EOF
STATE: $STATE
NEXT_ACTION: $NEXT_ACTION
ROLE: $ROLE
READ: $READ
MAY_EDIT: $MAY_EDIT
MUST_NOT_EDIT: $MUST_NOT_EDIT
BLOCKERS: ${BLOCKERS}
CURRENT_WORK_UNIT: $CWU
COMPLETION_CONDITION: $CC
EOF
