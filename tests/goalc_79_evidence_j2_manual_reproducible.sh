#!/usr/bin/env bash
# GOALC #79: J2 — judgment evidence (manual_observation / runtime_boundary=manual)
#            marked reproducible:true must declare a sensor_scope field bounding
#            what the sensor verifies. Without it, evidence check rejects the
#            entry (closes the velentrade P2-002 "ls *.png lends objective aura"
#            gap). Non-manual reproducible evidence is unchanged (backward compat).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-79
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p79"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"

# write_evidence <completion_level> <runtime_boundary> <reproducible> <extra-yaml-lines>
write_evidence() {
  local cl="$1" rb="$2" repro="$3" extra="$4"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: $rb
    persistence: memory
    completion_level: $cl
    reproducible: $repro
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
$extra
YML
}

# Case A: manual_observation + reproducible:true + NO sensor_scope -> reject
write_evidence manual_observation browser true ""
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  bad "J2-A: manual+reproducible without sensor_scope accepted (should reject)"
else
  ok "J2-A: manual+reproducible without sensor_scope rejected"
fi

# Case B: manual_observation + reproducible:true + sensor_scope -> accept
write_evidence manual_observation browser true "    sensor_scope: artifact_existence_only"
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  ok "J2-B: manual+reproducible with sensor_scope accepted"
else
  bad "J2-B: manual+reproducible with sensor_scope rejected (should accept)"
fi

# Case C: manual_observation + reproducible:false -> accept (no sensor_scope needed)
write_evidence manual_observation browser false ""
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  ok "J2-C: manual+reproducible=false accepted (no sensor_scope needed)"
else
  bad "J2-C: manual+reproducible=false rejected (should accept)"
fi

# Case D: non-manual (integrated_runtime) + reproducible:true + no sensor_scope -> accept (unchanged)
write_evidence integrated_runtime browser true ""
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  ok "J2-D: non-manual reproducible unchanged (backward compatible)"
else
  bad "J2-D: non-manual reproducible rejected (regression)"
fi

# Case E: runtime_boundary=manual + reproducible:true + no sensor_scope -> reject
write_evidence integrated_runtime manual true ""
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  bad "J2-E: runtime_boundary=manual+reproducible without sensor_scope accepted (should reject)"
else
  ok "J2-E: runtime_boundary=manual+reproducible without sensor_scope rejected"
fi

# Case F: sensor_scope present but EMPTY string -> still reject (must be non-empty)
write_evidence manual_observation browser true "    sensor_scope: \"\""
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  bad "J2-F: empty sensor_scope accepted (should reject)"
else
  ok "J2-F: empty sensor_scope rejected"
fi

[ "$TESTS_FAIL" -eq 0 ]
