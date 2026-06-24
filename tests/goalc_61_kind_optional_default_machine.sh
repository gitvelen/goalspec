#!/usr/bin/env bash
# GOALC #61: criterion `kind` is optional and defaults to machine.
#   - omitted kind   -> freeze passes (treated as machine)
#   - kind: judgment  -> freeze passes
#   - kind: <bogus>   -> freeze blocked (invalid kind)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

setup_awaiting() {
  fresh_initialized_repo "goalc-61-$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  "$REPO_GS" compile >/dev/null
}

apply_review_and_approve() {
  local tmp="$TESTS_TMP_ROOT/p61-$1"; mkdir -p "$tmp"
  cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

# Case A: omitted kind defaults to machine — freeze passes.
setup_awaiting a
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
apply_review_and_approve a
if "$REPO_GS" freeze >/dev/null 2>&1; then
  ok "freeze passed: omitted kind defaults to machine"
else
  bad "freeze blocked: omitted kind should default to machine"
fi

# Case B: explicit kind: judgment — freeze passes.
setup_awaiting b
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: judgment
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
apply_review_and_approve b
if "$REPO_GS" freeze >/dev/null 2>&1; then
  ok "freeze passed: explicit kind: judgment accepted"
else
  bad "freeze blocked: kind: judgment should be accepted"
fi

# Case C: invalid kind — freeze blocked.
setup_awaiting c
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: bogus
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
apply_review_and_approve c
if "$REPO_GS" freeze >/dev/null 2>&1; then
  bad "freeze passed: invalid kind should be blocked"
else
  ok "freeze blocked: invalid kind rejected"
fi

[ "$TESTS_FAIL" -eq 0 ]
