#!/usr/bin/env bash
# GOALC #27: intake packages include constraint suggestions that must be
# approved and applied before compile.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-27-package
"$REPO_GS" intake begin "cache generated TTS output without changing audio semantics" >/dev/null

[ -f "$REPO/.goalspec/active/constraint-suggestions.yaml" ] \
  && ok "intake begin creates constraint-suggestions.yaml" \
  || bad "intake begin did not create constraint-suggestions.yaml"

"$REPO_GS" intake end >/dev/null
"$REPO_GS" status | /bin/grep -q 'constraint-suggestions.yaml' \
  && ok "closed intake status asks for constraint suggestions" \
  || bad "closed intake status did not mention constraint suggestions"

cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Cache generated TTS output.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge:
    stack:
      languages:
        - Python
      package_managers:
        - pip
    commands:
      test:
        - pytest
project_constraints:
  - id: security-no-user-text-logs
    category: security
    level: hard
    statement: Do not log original user text.
    source_refs:
      - conversation
    applies_to:
      - all-goals
goal_constraints:
  - id: goal-cache-audio-semantics
    level: hard
    statement: Cache must not change generated audio semantics.
    source_refs:
      - conversation
open_questions: []
discarded_candidates: []
YML

if "$REPO_GS" intake apply-suggestions >/dev/null 2>&1; then
  bad "apply-suggestions succeeded without intake-package approval"
else
  ok "apply-suggestions blocks without intake-package approval"
fi

stamp_intake_capture_review_pass
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null \
  && ok "apply-suggestions succeeds after package approval" \
  || bad "apply-suggestions failed after package approval"

yq e '.stack.languages[]' "$REPO/.goalspec/project/profile.yaml" | /bin/grep -q '^Python$' \
  && ok "project profile suggestions merged" \
  || bad "project profile suggestions were not merged"
yq e '.constraints[] | select(.id == "security-no-user-text-logs") | .statement' "$REPO/.goalspec/project/constraints.yaml" | /bin/grep -q 'Do not log original user text' \
  && ok "project constraints suggestions appended" \
  || bad "project constraints suggestions were not appended"

make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null \
  && ok "compile accepts approved and applied intake package" \
  || bad "compile rejected approved and applied intake package"

echo '# changed' >> "$REPO/.goalspec/active/constraint-suggestions.yaml"
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile accepted stale intake-package approval"
else
  ok "compile blocks stale intake-package approval"
fi

fresh_initialized_repo goalc-27-source
mkdir -p "$REPO/docs"
cat > "$REPO/docs/spec.md" <<'MD'
# Spec
Cache generated TTS output. Must not log original user text.
MD
"$REPO_GS" new-goal --source docs/spec.md "cache generated TTS output" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal

if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile accepted sourced goal without intake package approval/application"
else
  ok "compile blocks sourced goal without intake package approval/application"
fi

[ "$TESTS_FAIL" -eq 0 ]
