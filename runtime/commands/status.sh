#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

mode="text"
if [ "${1:-}" = "--json" ]; then mode="json"; fi

state_file="$GOALSPEC_ROOT/active/state.yaml"
cf="$GOALSPEC_ROOT/active/contract.yaml"
vf="$GOALSPEC_ROOT/active/verdict.yaml"

STATE="no_goal"
GOAL="(none)"
FROZEN="false"
PROMPT_READY="false"
RUN_ALLOWED="false"
NEEDS_HUMAN_CONFIRMATION="false"
BLOCKERS=""
UNMET_CRITERIA=""
NEXT_USER_ACTION="Run /goalspec start <intent> to open a formal intake window."

if [ -f "$state_file" ]; then
  raw_state="$(yq e '.status // "draft"' "$state_file")"
  gid="$(yq e '.active_goal_id // ""' "$state_file")"
  if [ -n "$gid" ] && [ "$gid" != "null" ]; then
    STATE="$raw_state"
  fi
fi

if [ -f "$GOALSPEC_ROOT/active/goal.md" ]; then
  GOAL="$(awk '
    /^## .*Intent/ { in_intent=1; next }
    /^## / && in_intent { exit }
    in_intent && NF { print; exit }
  ' "$GOALSPEC_ROOT/active/goal.md")"
  [ -n "$GOAL" ] || GOAL="(draft goal present)"
fi

if [ -f "$cf" ] && [ "$(yq e '.status // ""' "$cf")" = "frozen" ]; then
  if [ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] \
    && [ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] \
    && [ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] \
    && [ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ]; then
    FROZEN="true"
  else
    BLOCKERS="${BLOCKERS}frozen_artifact_stale "
  fi
fi

if [ -f "$GOALSPEC_ROOT/active/goal-driven-prompt.md" ] \
  && [ "$(yq e '.prompt_hash // ""' "$state_file" 2>/dev/null || echo "")" = "$(goalspec_prompt_hash)" ] \
  && [ "$FROZEN" = "true" ]; then
  PROMPT_READY="true"
fi

nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$GOALSPEC_ROOT/active/questions.yaml" 2>/dev/null || echo 0)"
if [ "${nblock:-0}" -gt 0 ]; then
  BLOCKERS="${BLOCKERS}blocking_questions "
fi

if [ "$PROMPT_READY" = "true" ] && [ "${nblock:-0}" -eq 0 ]; then
  RUN_ALLOWED="true"
fi

if [ -f "$cf" ]; then
  required_ids="$(yq e '.criteria[] | select(.required_for_completion != false or .final == true or .priority == "P0") | .id' "$cf" 2>/dev/null || true)"
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    v="$(yq e "[.verdicts[] | select(.criteria_ref == \"$cid\")] | .[-1].verdict // \"\"" "$vf" 2>/dev/null || true)"
    [ "$v" = "pass" ] || UNMET_CRITERIA="${UNMET_CRITERIA}${cid} "
  done <<<"$required_ids"
fi
[ -n "$UNMET_CRITERIA" ] || UNMET_CRITERIA="(none)"

case "$STATE" in
  no_goal)
    NEXT_USER_ACTION="Run /goalspec start <intent> to open a formal intake window."
    ;;
  draft)
    intake_status="$(yq e '.intake_session.status // "not_started"' "$state_file" 2>/dev/null || echo "not_started")"
    if [ "$intake_status" = "collecting" ]; then
      NEXT_USER_ACTION="Continue capturing .goalspec/active/intake-conversation.md, add source with /goalspec source <path>, or run /goalspec end."
    else
      NEEDS_HUMAN_CONFIRMATION="true"
      NEXT_USER_ACTION="Draft Goal, Criteria, Constraints, out-of-scope, and blocking questions from .goalspec/active/intake-capture.md and .goalspec/active/constraint-suggestions.yaml; then ask for confirmation."
    fi
    ;;
  intake_reviewed|contract_draft|contract_reviewed)
    NEEDS_HUMAN_CONFIRMATION="true"
    NEXT_USER_ACTION="Review and explicitly confirm the drafted Goal, Criteria, and Constraints before freezing."
    ;;
  prompt_ready)
    NEXT_USER_ACTION="Run /goalspec run to begin implementation from the frozen Goal-Driven Prompt."
    ;;
  running)
    NEXT_USER_ACTION="Execute the Goal-Driven Prompt; continue until required Criteria pass or a human blocker requires reopen."
    ;;
  completed)
    NEXT_USER_ACTION="Goal completed. Run /goalspec start <intent> for another goal."
    ;;
  blocked|reopen_required)
    NEEDS_HUMAN_CONFIRMATION="true"
    NEXT_USER_ACTION="Resolve the blocker or run /goalspec reopen <reason>."
    ;;
esac

sb="$(goalspec_stale_blockers)"
if [ -n "$sb" ]; then
  BLOCKERS="${BLOCKERS}stale: ${sb}"
  RUN_ALLOWED="false"
fi
[ -n "$BLOCKERS" ] || BLOCKERS="(none)"

if [ "$mode" = "json" ]; then
  yq -o=json -I=0 '.' <<EOF
state: "$STATE"
goal: "$GOAL"
frozen: $FROZEN
prompt_ready: $PROMPT_READY
run_allowed: $RUN_ALLOWED
needs_human_confirmation: $NEEDS_HUMAN_CONFIRMATION
blockers: "$BLOCKERS"
unmet_criteria: "$UNMET_CRITERIA"
next_user_action: "$NEXT_USER_ACTION"
EOF
  exit 0
fi

cat <<EOF
STATE: $STATE
GOAL: $GOAL
FROZEN: $FROZEN
PROMPT_READY: $PROMPT_READY
RUN_ALLOWED: $RUN_ALLOWED
NEEDS_HUMAN_CONFIRMATION: $NEEDS_HUMAN_CONFIRMATION
BLOCKERS: $BLOCKERS
UNMET_CRITERIA: $UNMET_CRITERIA
NEXT_USER_ACTION: $NEXT_USER_ACTION
EOF
