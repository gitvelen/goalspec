#!/usr/bin/env bash
# GOALC #53: derived loop-contract view (Tier 3). `goalspec status` renders a
# read-only 11-item LOOP_CONTRACT section once the contract is frozen — assembled
# from existing artifacts, no new writable file.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P53="$TESTS_TMP_ROOT/p53"; mkdir -p "$P53"

fresh_initialized_repo goalc-53
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$P53/c.yaml"
"$REPO_GS" review apply "$P53/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

# Before freeze there would be no LOOP_CONTRACT; verify it appears once frozen.
"$REPO_GS" status > "$P53/status.txt" 2>&1
grep -q "^LOOP_CONTRACT:" "$P53/status.txt" && ok "status renders LOOP_CONTRACT when frozen" || bad "no LOOP_CONTRACT section"

# All 11 keys present.
miss=""
for k in name trigger goal input scope tools verification stop escalation state cleanup; do
  grep -q "^[[:space:]]*${k}:" "$P53/status.txt" || miss="${miss}${k} "
done
[ -z "$miss" ] && ok "all 11 loop-contract keys present" || bad "missing keys: $miss"

# stop reflects profile thresholds.
grep -q "max_iterations=8" "$P53/status.txt" && ok "stop shows max_iterations" || bad "stop missing max_iterations"
grep -q "stall_threshold=3" "$P53/status.txt" && ok "stop shows stall_threshold" || bad "stop missing stall_threshold"

# scope reflects the contract allowed_paths.
grep -q "src/\*\*" "$P53/status.txt" && ok "scope reflects contract allowed_paths" || bad "scope missing allowed_paths"

# After a judge-apply round, the state line reflects iteration.
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
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
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
ehash="$(cur_evidence_hash)"
cat > "$P53/v.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: fail
reason: pending
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$P53/v.yaml" >/dev/null
"$REPO_GS" status > "$P53/status2.txt" 2>&1
grep -q "iteration=1" "$P53/status2.txt" && ok "state reflects iteration after a round" || bad "state line does not reflect iteration"

# The render writes no new artifact to active/.
[ ! -f "$REPO/.goalspec/active/loop-contract.yaml" ] && ok "render writes no new artifact" || bad "render created a new file"

# During intake (no frozen contract) the section is absent.
fresh_initialized_repo goalc-53-nocontract
"$REPO_GS" status > "$P53/status3.txt" 2>&1
grep -q "^LOOP_CONTRACT:" "$P53/status3.txt" && bad "LOOP_CONTRACT rendered before freeze" || ok "no LOOP_CONTRACT before freeze"

[ "$TESTS_FAIL" -eq 0 ]
