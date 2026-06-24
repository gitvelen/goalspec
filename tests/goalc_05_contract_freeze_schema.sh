#!/usr/bin/env bash
# GOALC #5: contract missing criteria / no final criterion / vague or
#            implementation-step statements -> freeze fails.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-05
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
tmp="$TESTS_TMP_ROOT/p5"; mkdir -p "$tmp"
cat > "$tmp/contract-pass.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML

run_freeze_should_fail() {
  local label="$1"
  "$REPO_GS" review apply "$tmp/contract-pass.yaml" >/dev/null 2>&1 || true
  "$REPO_GS" approve contract >/dev/null 2>&1 || true
  if "$REPO_GS" freeze >/dev/null 2>&1; then
    bad "freeze succeeded: $label"
  else
    ok "freeze blocked: $label"
  fi
  # reset contract status back to draft for next iteration (review/contract approval state may persist; that's fine).
}

# Case A: no criteria
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria: []
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
YML
run_freeze_should_fail "no criteria"

# Case B: no final criteria
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    statement: behavior A observed
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
YML
run_freeze_should_fail "no final criteria"

# Case C: vague statement (fails the Clear lint, enhance.md §6)
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    statement: the behavior is good and complete
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
YML
run_freeze_should_fail "vague statement"

# Case D: statement encodes an implementation step (fails the Minimal lint)
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    statement: implement the snake module
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
YML
run_freeze_should_fail "implementation-step statement"

[ "$TESTS_FAIL" -eq 0 ]
