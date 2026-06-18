#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

mode="text"
if [ "${1:-}" = "--json" ]; then mode="json"; fi

STATE="(no active goal)"
NEXT_ACTION="Run: goalspec intake begin [text] for conversation capture, or goalspec new-goal [--source <path>] [text]"
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
  # If active_goal_id is null, there is no active goal yet — route to new-goal.
  gid="$(yq e '.active_goal_id // ""' "$state_file")"
  if [ -z "$gid" ] || [ "$gid" = "null" ]; then
    STATE="(no active goal)"
  fi
fi

# Derive NEXT_ACTION / ROLE / boundaries from state.
case "$STATE" in
  draft)
    intake_status="$(yq e '.intake_session.status // "not_started"' "$state_file" 2>/dev/null || echo "not_started")"
    if [ "$intake_status" = "collecting" ]; then
      NEXT_ACTION="Record begin/end conversation in active/intake-conversation.md; add sources with goalspec intake add-source <path>; then: goalspec intake end"
      ROLE="intake"
      READ=".goalspec/ai/core.md, .goalspec/ai/intake.md, .goalspec/active/intake-conversation.md, .goalspec/active/intake-sources.yaml"
      MAY_EDIT=".goalspec/active/intake-conversation.md, .goalspec/active/intake-sources.yaml, .goalspec/active/questions.yaml, .goalspec/artifacts/intake/**"
      MUST_NOT_EDIT=".goalspec/active/goal.md, .goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/project/**"
    elif goalspec_intake_has_sources && { ! yq e '[.approvals[] | select(.kind == "intake-package")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; }; then
      NEXT_ACTION="Write active/intake-capture.md and active/constraint-suggestions.yaml from conversation/source material, then ask human confirmation and run: goalspec approve intake-package -> goalspec intake apply-suggestions"
      ROLE="intake"
      READ=".goalspec/ai/core.md, .goalspec/ai/intake.md, .goalspec/active/intake-conversation.md, .goalspec/active/intake-sources.yaml"
      MAY_EDIT=".goalspec/active/intake-capture.md, .goalspec/active/constraint-suggestions.yaml, .goalspec/active/questions.yaml"
      MUST_NOT_EDIT=".goalspec/active/goal.md, .goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/project/**"
    elif goalspec_intake_has_sources && goalspec_approval_stale intake-package; then
      NEXT_ACTION="Re-approve changed active/intake-capture.md / active/constraint-suggestions.yaml: goalspec approve intake-package, then goalspec intake apply-suggestions"
      ROLE="human"
      READ=".goalspec/active/intake-capture.md, .goalspec/active/constraint-suggestions.yaml, .goalspec/active/intake-conversation.md"
      MAY_EDIT="(nothing)"
      MUST_NOT_EDIT=".goalspec/active/goal.md, .goalspec/active/contract.yaml, business code"
    else
      NEXT_ACTION="Write active/goal.md from approved intake package and/or source snapshots, including goal constraints from active/constraint-suggestions.yaml, then: goalspec review prompt intake -> goalspec review apply"
      ROLE="intake"
      READ=".goalspec/ai/core.md, .goalspec/ai/intake.md, .goalspec/active/goal.md, .goalspec/active/intake-capture.md, .goalspec/active/constraint-suggestions.yaml, .goalspec/active/intake-sources.yaml"
      MAY_EDIT=".goalspec/active/goal.md, .goalspec/active/questions.yaml"
      MUST_NOT_EDIT=".goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, .goalspec/project/**"
    fi
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
