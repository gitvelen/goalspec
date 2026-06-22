#!/usr/bin/env bash
# GOALC #31: goal-driven command surface, prompt generation, and run gate.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

setup_frozen_goal_driven() {
  fresh_initialized_repo "$1"
  "$REPO_GS" start "ship goal-driven run gate" >/dev/null
  "$REPO_GS" source AGENTS.md >/dev/null
  "$REPO_GS" end >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Ship a run gate.
MD
  cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
  "$REPO_GS" approve intake-package >/dev/null
  "$REPO_GS" intake apply-suggestions >/dev/null
  approve_intake_and_goal
  compile_to_awaiting_confirmation
  do_freeze
}

fresh_initialized_repo goalc-31-command-surface
"$REPO_GS" start "capture this intent" >/dev/null
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "collecting" ] \
  && ok "start opens formal intake window" \
  || bad "start did not open intake"

"$REPO_GS" source AGENTS.md >/dev/null
yq e '[.sources[] | select(.path == "AGENTS.md")] | length' "$REPO/.goalspec/active/intake-sources.yaml" | grep -q '^1$' \
  && ok "source adds material to open intake" \
  || bad "source did not add intake material"

if "$REPO_GS" run >/dev/null 2>"$TESTS_TMP_ROOT/run-before-freeze.err"; then
  bad "run succeeded before frozen artifacts"
else
  /bin/grep -q 'GOALSPEC_RUN_ALLOWED: false' "$TESTS_TMP_ROOT/run-before-freeze.err" \
    || /bin/grep -q 'GOALSPEC_RUN_ALLOWED: false' "$TESTS_TMP_ROOT/run-before-freeze.err" \
    && ok "run refuses before frozen artifacts" \
    || bad "run refusal did not print false envelope"
fi

"$REPO_GS" end >/dev/null
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "end closes formal intake window" \
  || bad "end did not close intake"

setup_frozen_goal_driven goalc-31-run-ready
prompt="$REPO/.goalspec/active/goal-driven-prompt.md"
[ -f "$prompt" ] \
  && ok "freeze generates goal-driven prompt" \
  || bad "freeze did not generate prompt"

/bin/grep -q 'Goal-Driven' "$prompt" \
  && /bin/grep -q 'Master Agent' "$prompt" \
  && /bin/grep -q 'Primary Subagent' "$prompt" \
  && /bin/grep -q 'Worker Subagents' "$prompt" \
  && /bin/grep -q 'Agent roles are execution roles only' "$prompt" \
  && /bin/grep -q 'Agent Execution Roles' "$prompt" \
  && /bin/grep -q 'bounded, Criteria-linked' "$prompt" \
  && /bin/grep -q 'Loop Procedure' "$prompt" \
  && /bin/grep -q 'Master Evaluation' "$prompt" \
  && /bin/grep -q 'Evidence / Progress Report' "$prompt" \
  && /bin/grep -q 'Master Verdict' "$prompt" \
  && /bin/grep -q 'Criteria Coverage Audit' "$prompt" \
  && /bin/grep -q 'atomic claim lacks sufficient evidence' "$prompt" \
  && /bin/grep -q 'Master Heartbeat Policy' "$prompt" \
  && /bin/grep -q 'about every 5 minutes' "$prompt" \
  && /bin/grep -q 'Do not stop merely because one Subagent attempt finishes' "$prompt" \
  && /bin/grep -q 'Goalspec CLI runtime does not itself' "$prompt" \
  && /bin/grep -q 'Criteria satisfaction is the only success condition' "$prompt" \
  && /bin/grep -q 'Subagent cannot declare final success' "$prompt" \
  && ok "prompt contains explicit master/subagent loop and heartbeat protocol" \
  || bad "prompt missing goal-driven loop protocol"

out="$("$REPO_GS" run)"
echo "$out" | /bin/grep -q 'GOALSPEC_RUN_ALLOWED: true' \
  && echo "$out" | /bin/grep -q 'PROMPT_FILE: .goalspec/active/goal-driven-prompt.md' \
  && echo "$out" | /bin/grep -q 'READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true' \
  && ok "run prints allowed execution envelope" \
  || bad "run did not print allowed execution envelope"

echo "$out" | /bin/grep -q '# Goal-Driven' \
  && ok "run prints full prompt" \
  || bad "run did not print full prompt"

echo "tamper" >> "$REPO/.goalspec/active/criteria.yaml"
if "$REPO_GS" run >/dev/null 2>"$TESTS_TMP_ROOT/run-stale.err"; then
  bad "run succeeded with stale prompt"
else
  /bin/grep -q 'GOALSPEC_RUN_ALLOWED: false' "$TESTS_TMP_ROOT/run-stale.err" \
    && /bin/grep -qi 'stale' "$TESTS_TMP_ROOT/run-stale.err" \
    && ok "run blocks stale prompt" \
    || bad "stale run blocker missing"
fi

if "$REPO_GS" help | /bin/grep -q '^  next[[:space:]]'; then
  bad "help exposes next as user command"
else
  ok "help hides next from user command surface"
fi

[ "$TESTS_FAIL" -eq 0 ]
