#!/usr/bin/env bash
# GOALC #4: goal.md missing Narrative/Success Model/Scope/Risk Scan, or has a
#            blocking open question, must not pass intake review.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-04
"$REPO_GS" new-goal "test" >/dev/null

# Empty goal.md (just title) -> intake review apply pass must be rejected
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal
MD
tmp="$TESTS_TMP_ROOT/p4"; mkdir -p "$tmp"
cat > "$tmp/intake-pass.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
if "$REPO_GS" review apply "$tmp/intake-pass.yaml" >/dev/null 2>&1; then
  bad "intake review pass accepted on empty goal.md"
else
  ok "intake review pass rejected on empty goal.md"
fi

# Now a goal.md missing the Risk Scan section
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal

## 1. Intent
X.

## 2. Narrative
N.

## 3. Success Model
- user_visible_success: a

## 4. Scope
- in_scope: x
MD
if "$REPO_GS" review apply "$tmp/intake-pass.yaml" >/dev/null 2>&1; then
  bad "intake review pass accepted with missing Risk Scan"
else
  ok "intake review pass rejected with missing Risk Scan"
fi

# Complete goal.md but with an unresolved blocking open question
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
cat > "$REPO/.goalspec/active/questions.yaml" <<'YML'
questions:
  - id: Q-001
    blocking: true
    status: open
    question: unresolved blocking
YML
if "$REPO_GS" review apply "$tmp/intake-pass.yaml" >/dev/null 2>&1; then
  bad "intake review pass accepted with unresolved blocking question"
else
  ok "intake review pass rejected with unresolved blocking question"
fi

[ "$TESTS_FAIL" -eq 0 ]
