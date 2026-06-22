#!/usr/bin/env bash
# GOALC #32: criteria lint and optional criteria completion behavior.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

setup_contract_spec() {
  fresh_initialized_repo "$1"
  "$REPO_GS" new-goal "criteria lint test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  "$REPO_GS" compile >/dev/null
}

setup_contract_spec goalc-32-lint
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
criteria:
  - id: CRIT-001
    statement: 完整正确支持目标
    final: true
evidence_requirements: []
constraints: []
YML
tmp_lint="$TESTS_TMP_ROOT/p32-lint"; mkdir -p "$tmp_lint"
cat > "$tmp_lint/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp_lint/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null

if "$REPO_GS" freeze >/dev/null 2>"$TESTS_TMP_ROOT/lint.err"; then
  bad "freeze accepted vague criteria"
else
  /bin/grep -q 'criteria CRIT-001' "$TESTS_TMP_ROOT/lint.err" \
    && /bin/grep -q 'vague' "$TESTS_TMP_ROOT/lint.err" \
    && ok "freeze rejects vague criteria" \
    || bad "criteria lint did not report vague criterion"
fi

fresh_initialized_repo goalc-32-optional
"$REPO_GS" new-goal "optional criteria should not block complete" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    statement: User submits the core form and sees saved output.
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    final: true
    statement: Master Agent verifies the required criteria pass from evidence.
    evidence_requirement_refs: [EVIDREQ-001]
optional_criteria:
  - id: OPT-001
    statement: User can export an additional report.
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
tmp="$TESTS_TMP_ROOT/p32"; mkdir -p "$tmp" "$REPO/src"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null || bad "freeze rejected required-by-default criteria"

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
echo "done" > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
    attempt: A1
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: "2026-06-15T00:00:00Z"
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"
for crit in CRIT-001 CRIT-FINAL-001; do
  cat > "$tmp/$crit.yaml" <<YML
criteria_ref: $crit
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "test criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$tmp/$crit.yaml" >/dev/null || bad "judge apply failed for $crit"
done

cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      summary: core path works
YML
"$REPO_GS" approve memory-patch >/dev/null
"$REPO_GS" complete >/dev/null \
  && ok "optional criteria do not block completion" \
  || bad "optional criteria blocked completion"

[ "$TESTS_FAIL" -eq 0 ]
