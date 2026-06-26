#!/usr/bin/env bash
# GOALC #66: goal-driven-prompt loads project-level constraints (long-term,
# all goals) so the run-loop honors them. Without this, project/constraints.yaml
# was invisible to Master/Subagent execution (constraints had no teeth).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# --- Branch A: project has a level:hard long-term constraint ---------------
fresh_initialized_repo goalc-66-prompt-constraints
"$REPO_GS" start "ship with project constraint loaded" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Ship with a project constraint loaded into the prompt.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints:
  - id: security-no-secret-logs
    category: security
    level: hard
    statement: Do not log secrets or credentials.
    source_refs:
      - conversation
    applies_to:
      - all-goals
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

prompt="$REPO/.goalspec/active/goal-driven-prompt.md"
[ -f "$prompt" ] && ok "freeze generated prompt" || { bad "no prompt"; false; }

/bin/grep -q 'Project Constraints (long-term, all goals)' "$prompt" \
  && ok "prompt has Project Constraints section" \
  || bad "prompt missing Project Constraints section"

/bin/grep -q 'security-no-secret-logs' "$prompt" \
  && /bin/grep -q 'Do not log secrets or credentials' "$prompt" \
  && ok "prompt inlines project constraint id and statement" \
  || bad "prompt did not inline project constraint content"

/bin/grep -q 'Goal-level Constraints (this change)' "$prompt" \
  && ok "prompt distinguishes goal-level constraints section" \
  || bad "prompt missing goal-level constraints section"

/bin/grep -q 'Constraint Conformance' "$prompt" \
  && /bin/grep -q 'Constraint violation: <constraint_id>' "$prompt" \
  && ok "prompt instructs Master on Constraint Conformance duty" \
  || bad "prompt missing Constraint Conformance instruction"

# --- Branch B: project has NO long-term constraints; prompt degrades cleanly -
fresh_initialized_repo goalc-66-no-project-constraints
"$REPO_GS" start "no project constraints" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
No project constraints.
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
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

prompt2="$REPO/.goalspec/active/goal-driven-prompt.md"
/bin/grep -q 'Project Constraints (long-term, all goals)' "$prompt2" \
  && ok "prompt still emits Project Constraints section when none defined" \
  || bad "prompt dropped Project Constraints section when none defined"

[ "$TESTS_FAIL" -eq 0 ]
