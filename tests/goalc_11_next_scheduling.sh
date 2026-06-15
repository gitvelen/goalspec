#!/usr/bin/env bash
# GOALC #11: next returns one WU at a time; if current WU's latest verdict is
#            fail/insufficient, next must return the same WU.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-11
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal

# Two work units with a dependency chain.
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: x
project_memory_hash: x
contract_hash: null
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: a
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-002
    priority: P0
    required_for_completion: true
    statement: b
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    priority: P0
    required_for_completion: true
    final: true
    statement: c
    evidence_requirement_refs: [EVIDREQ-001]
work_units:
  - id: WU-001
    goal: first
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["src/**"]
  - id: WU-002
    goal: second
    depends_on: [WU-001]
    criteria_refs: [CRIT-002]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["src/**"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: x
    criteria_refs: [CRIT-001]
constraints: []
required_regressions: []
YML
tmp="$TESTS_TMP_ROOT/p11"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

# next should return WU-001
out="$("$REPO_GS" next)"
echo "$out" | /bin/grep -q 'WU-001' && ok "next returns WU-001 first"

# Build a verdict: fail for CRIT-001.
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: executor
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"
cat > "$tmp/vfail.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: not yet
context: fresh
judged_by: guardian
YML
"$REPO_GS" judge apply "$tmp/vfail.yaml" >/dev/null

# next should return WU-001 again (same WU on fail)
out="$("$REPO_GS" next)"
if echo "$out" | /bin/grep -q 'CURRENT_WORK_UNIT: WU-001'; then
  ok "next returns same WU-001 on fail verdict"
else
  bad "next did not return WU-001 after fail; got: $out"
fi

# Also verify WU-002 is never returned before WU-001 passes.
if echo "$out" | /bin/grep -q 'WU-002'; then
  bad "next returned WU-002 despite WU-001 failing"
fi

[ "$TESTS_FAIL" -eq 0 ]
