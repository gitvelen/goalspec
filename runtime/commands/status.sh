#!/usr/bin/env bash
set -uo pipefail
# Ignore SIGPIPE: callers commonly pipe `status` into `grep -q` / `head`, which
# close the read end early. The LOOP_CONTRACT render below spawns yq, so output
# may still be in flight when the reader exits — without this, status would die
# on SIGPIPE (141) and, under the caller's `pipefail`, report a false failure.
trap '' PIPE
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

mode="text"
if [ "${1:-}" = "--json" ]; then mode="json"; fi

state_file="$GOALSPEC_ROOT/active/state.yaml"
cf="$GOALSPEC_ROOT/active/contract.yaml"
vf="$GOALSPEC_ROOT/active/verdict.yaml"
cpf="$GOALSPEC_ROOT/active/close-package.yaml"

STATE="no_goal"
GOAL="(none)"
FROZEN="false"
PROMPT_READY="false"
RUN_ALLOWED="false"
CLOSE_READY="false"
NEEDS_HUMAN_CONFIRMATION="false"
BLOCKERS=""
CLOSE_BLOCKERS=""
UNMET_CRITERIA=""
NEXT_USER_ACTION="Run /goalspec start <intent> to open a formal intake window."

if [ -f "$state_file" ]; then
  raw_state="$(yq e '.status // "no_goal"' "$state_file")"
  gid="$(yq e '.active_goal_id // ""' "$state_file")"
  if [ -n "$gid" ] && [ "$gid" != "null" ]; then
    case "$raw_state" in
      prompt_ready|frozen_ready) STATE="ready_to_run" ;;
      *) STATE="$raw_state" ;;
    esac
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
    && [ "$(yq e '.goal_artifact_hash // ""' "$state_file")" = "$(goalspec_goal_artifact_hash)" ] \
    && [ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] \
    && [ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ]; then
    FROZEN="true"
  else
    BLOCKERS="${BLOCKERS}frozen_artifact_stale "
  fi
fi

if [ -f "$state_file" ] && [ -f "$cf" ] && [ "$(yq e '.status // ""' "$cf")" = "frozen" ]; then
  rec_scope="$(yq e '.scope_hash // ""' "$state_file")"
  cur_scope="$(goalspec_scope_hash)"
  if [ -n "$rec_scope" ] && [ "$rec_scope" != "null" ] && [ "$rec_scope" != "$cur_scope" ]; then
    BLOCKERS="${BLOCKERS}scope_stale "
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

if [ "$PROMPT_READY" = "true" ] && [ "${nblock:-0}" -eq 0 ] && [ "$STATE" != "ready_to_close" ] && [ "$STATE" != "closing" ] && [ "$STATE" != "closed" ]; then
  RUN_ALLOWED="true"
fi

if [ -f "$cf" ]; then
  required_ids="$(yq e '.criteria[].id' "$cf" 2>/dev/null || true)"
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    goalspec_close_criterion_has_fresh_pass "$cid" && continue
    k="$(yq e ".criteria[] | select(.id == \"$cid\") | .kind // \"machine\"" "$cf" 2>/dev/null || echo machine)"
    UNMET_CRITERIA="${UNMET_CRITERIA}${cid}(${k}) "
  done <<<"$required_ids"
fi
[ -n "$UNMET_CRITERIA" ] || UNMET_CRITERIA="(none)"

if [ "$FROZEN" = "true" ] && [ "$UNMET_CRITERIA" = "(none)" ] && [ "$STATE" != "closed" ]; then
  readiness_blockers="$(goalspec_close_readiness_blockers)"
  if [ -n "$readiness_blockers" ]; then
    CLOSE_BLOCKERS="$readiness_blockers"
    BLOCKERS="${BLOCKERS}close_readiness "
    CLOSE_READY="false"
  fi
fi

if [ "$STATE" = "ready_to_close" ] && [ -f "$cpf" ]; then
  if goalspec_close_validate_package_hashes >/dev/null 2>&1; then
    CLOSE_READY="true"
  else
    BLOCKERS="${BLOCKERS}close_package_stale "
    CLOSE_BLOCKERS="${CLOSE_BLOCKERS} close_package_stale"
  fi
fi

case "$STATE" in
  no_goal)
    NEXT_USER_ACTION="Run /goalspec start <intent> to open a formal intake window."
    ;;
  intake_collecting)
    NEXT_USER_ACTION="Continue capturing .goalspec/active/intake-conversation.md, add source with /goalspec source <path>, or run /goalspec end."
    ;;
  spec_drafting)
    NEEDS_HUMAN_CONFIRMATION="true"
    NEXT_USER_ACTION="AI drafts Goal, Criteria, Constraints, out-of-scope, blocking questions, intake-capture.md, and constraint-suggestions.yaml, then shows a concise review summary and waits for stage-specific confirmation."
    ;;
  awaiting_human_confirmation)
    NEEDS_HUMAN_CONFIRMATION="true"
    NEXT_USER_ACTION="Review the drafted Goal, Criteria, Constraints, intake-capture.md, and constraint-suggestions.yaml; use stage-specific confirmation before applying intake suggestions or freezing."
    ;;
  ready_to_run)
    NEXT_USER_ACTION="Run /goalspec run to begin implementation from the frozen Goal-Driven Prompt."
    ;;
  running)
    NEXT_USER_ACTION="Execute the Goal-Driven Prompt; continue until required Criteria pass, then run /goalspec run again to generate the close package."
    ;;
  ready_to_close)
    NEEDS_HUMAN_CONFIRMATION="true"
    NEXT_USER_ACTION="Review the close package delivery mode, then run /goalspec close to archive and execute the configured delivery."
    ;;
  closing)
    NEXT_USER_ACTION="Close is in progress or recoverable. Re-run /goalspec close to continue from the checkpoint."
    ;;
  closed)
    NEXT_USER_ACTION="Goal closed. Run /goalspec start <intent> for another change."
    ;;
  blocked|reopen_required)
    NEEDS_HUMAN_CONFIRMATION="true"
    if [ "$STATE" = "reopen_required" ]; then
      impact_status="$(yq e '.status // "missing"' "$GOALSPEC_ROOT/active/reopen-impact.yaml" 2>/dev/null || echo "missing")"
      NEXT_USER_ACTION="Review and complete reopen-impact.yaml (status=$impact_status), revise goal.md and/or contract.yaml, then re-review, re-approve, and freeze before running again."
    else
      NEXT_USER_ACTION="Resolve the blocker, then continue from the current lifecycle step."
    fi
    ;;
esac

# run-loop stop-loss signal: when the loop is capped, override the next action
# to force a human decision (Step 05) — the loop must not keep spending.
if [ "$(yq e '.run_loop.last_outcome // ""' "$state_file" 2>/dev/null)" = "capped" ]; then
  NEEDS_HUMAN_CONFIRMATION="true"
  NEXT_USER_ACTION="Run-loop reached the iteration cap (run_loop.iteration). Run /goalspec close if Criteria are actually met, or /goalspec reopen <reason> if the spec is wrong, then resume."
fi
# run-loop no-progress signal: stalled (verdict fingerprint + evidence unchanged
# for stall_threshold rounds) steers toward reopen — it signals a spec defect,
# not merely an exhausted budget.
if goalspec_run_loop_stalled_current; then
  NEEDS_HUMAN_CONFIRMATION="true"
  NEXT_USER_ACTION="Run-loop stalled: no progress for stall_threshold consecutive rounds (verdict fingerprint and evidence unchanged) — likely a spec defect. Run /goalspec reopen <reason> to revise the Goal/Criteria/Constraints, or /goalspec close if Criteria are actually met."
fi

sb="$(goalspec_stale_blockers)"
if [ -n "$sb" ]; then
  BLOCKERS="${BLOCKERS}stale: ${sb}"
  RUN_ALLOWED="false"
  CLOSE_READY="false"
fi
[ -n "$BLOCKERS" ] || BLOCKERS="(none)"
[ -n "$CLOSE_BLOCKERS" ] || CLOSE_BLOCKERS="(none)"

if [ "$mode" = "json" ]; then
  yq -o=json -I=0 '.' <<EOF
state: "$STATE"
goal: "$GOAL"
frozen: $FROZEN
prompt_ready: $PROMPT_READY
run_allowed: $RUN_ALLOWED
close_ready: $CLOSE_READY
needs_human_confirmation: $NEEDS_HUMAN_CONFIRMATION
blockers: "$BLOCKERS"
close_blockers: "$CLOSE_BLOCKERS"
unmet_criteria: "$UNMET_CRITERIA"
scope_hash: "$(goalspec_scope_hash 2>/dev/null || echo "")"
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
CLOSE_READY: $CLOSE_READY
NEEDS_HUMAN_CONFIRMATION: $NEEDS_HUMAN_CONFIRMATION
BLOCKERS: $BLOCKERS
CLOSE_BLOCKERS: $CLOSE_BLOCKERS
UNMET_CRITERIA: $UNMET_CRITERIA
SCOPE_HASH: $(goalspec_scope_hash 2>/dev/null || echo "")
NEXT_USER_ACTION: $NEXT_USER_ACTION
EOF

# Tier 3: derived 11-item loop-contract view (read-only, no new artifact).
# Only renders once the contract is frozen — there is no loop to describe
# during intake/drafting.
if [ "$FROZEN" = "true" ]; then
  {
    echo "LOOP_CONTRACT:"
    goalspec_loop_contract_render | sed 's/^/  /'
  } 2>/dev/null || true
fi
exit 0
