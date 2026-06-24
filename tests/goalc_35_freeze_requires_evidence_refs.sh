#!/usr/bin/env bash
# GOALC #35: freeze must require each criterion to carry resolvable
#            evidence_requirement_refs (enhance.md §6 Decidable) — a criterion
#            with no refs, or refs that dangle, must fail freeze.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-35
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
tmp="$TESTS_TMP_ROOT/p35"; mkdir -p "$tmp"
cat > "$tmp/contract-pass.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML

try_freeze_fail() {
  local label="$1"
  "$REPO_GS" review apply "$tmp/contract-pass.yaml" >/dev/null 2>&1 || true
  "$REPO_GS" approve contract >/dev/null 2>&1 || true
  if "$REPO_GS" freeze >"$TESTS_TMP_ROOT/goalc35.err" 2>&1; then
    bad "freeze succeeded: $label"
  else
    ok "freeze blocked: $label"
  fi
}

# Case A: criterion missing evidence_requirement_refs entirely
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    statement: behavior A observed
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
try_freeze_fail "criterion missing evidence_requirement_refs"

# Case B: evidence_requirement_refs dangle (no matching evidence_requirements id)
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-NOPE]
  - id: CRIT-FINAL-001
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-NOPE]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
try_freeze_fail "dangling evidence_requirement_refs"

[ "$TESTS_FAIL" -eq 0 ]
