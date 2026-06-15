#!/usr/bin/env bash
# GOALC #18: complete success must update project/memory.yaml, versions.yaml,
#            regression-suite.yaml and archive active files to history/vNNNN/.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-18
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p18"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" next >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
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

for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
judged_by: guardian
YML
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
done

cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-SNAKE-001
      statement: x
      status: active
  - kind: decision
    content:
      id: DEC-SNAKE-001
      statement: y
      status: active
  - kind: constraint
    content:
      id: CON-001
      type: hard
      category: x
      statement: z
      status: active
      source: human
  - kind: regression
    content:
      id: REG-001
      source_trace: TRACE-001
      description: r
      replay_command: t
      expected_result: "exit_code == 0"
YML
"$REPO_GS" approve memory-patch >/dev/null
"$REPO_GS" complete >/dev/null

# history/v0001 exists with all expected files.
hdir="$REPO/.goalspec/history/v0001"
[ -d "$hdir" ] || bad "no history/v0001"
for f in goal.md contract.yaml evidence.yaml verdict.yaml trace.yaml memory-patch.yaml summary.yaml; do
  [ -f "$hdir/$f" ] || bad "history missing $f"
done
ok "history/v0001 archived all active files"

# project memory updated.
mem_n="$(yq e '.capabilities | length' "$REPO/.goalspec/project/memory.yaml")"
[ "${mem_n:-0}" -ge 1 ] || bad "project/memory.yaml not updated"
ok "project/memory.yaml updated"

# versions.yaml updated.
v_n="$(yq e '.versions | length' "$REPO/.goalspec/project/versions.yaml")"
[ "${v_n:-0}" -ge 1 ] || bad "versions.yaml not updated"
ok "project/versions.yaml updated"

# regression-suite updated with locked regression.
reg_status="$(yq e '.regressions[-1].status' "$REPO/.goalspec/project/regression-suite.yaml")"
[ "$reg_status" = "locked" ] || bad "regression-suite not updated/locked"
ok "project/regression-suite.yaml updated with locked regression"

[ "$TESTS_FAIL" -eq 0 ]
