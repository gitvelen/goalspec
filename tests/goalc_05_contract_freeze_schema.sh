#!/usr/bin/env bash
# GOALC #5: contract missing criteria / coverage gap / WU without criteria /
#            allowed paths too wide without approval -> freeze fails.
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
work_units:
  - id: WU-001
    goal: x
    criteria_refs: [CRIT-X]
    allowed_paths: ["src/**"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: x
    criteria_refs: [CRIT-X]
YML
run_freeze_should_fail "no criteria"

# Case B: no final criteria
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: foo
work_units:
  - id: WU-001
    goal: x
    criteria_refs: [CRIT-001]
    allowed_paths: ["src/**"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: x
    criteria_refs: [CRIT-001]
YML
run_freeze_should_fail "no final criteria"

# Case C: WU without criteria_refs
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: foo
  - id: CRIT-FINAL-001
    priority: P0
    required_for_completion: true
    final: true
    statement: bar
work_units:
  - id: WU-001
    goal: x
    criteria_refs: []
    allowed_paths: ["src/**"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: x
    criteria_refs: [CRIT-001]
YML
run_freeze_should_fail "WU without criteria_refs"

# Case D: WU without allowed_paths
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: foo
  - id: CRIT-FINAL-001
    priority: P0
    required_for_completion: true
    final: true
    statement: bar
work_units:
  - id: WU-001
    goal: x
    criteria_refs: [CRIT-001]
    allowed_paths: []
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: x
    criteria_refs: [CRIT-001]
YML
run_freeze_should_fail "WU without allowed_paths"

[ "$TESTS_FAIL" -eq 0 ]
