#!/usr/bin/env bash
# GOALC #7: contract.yaml change makes old evidence / verdict stale; judge apply /
#            complete must not accept old hash.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-07
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p7"; mkdir -p "$tmp"
cat > "$tmp/contract-pass.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract-pass.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
# produce an evidence entry
mkdir -p "$REPO/src"
echo "x" > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "browser-test"
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
EHASH="$(cur_evidence_hash)"

# judge apply a pass verdict with correct hashes
cat > "$tmp/v1.yaml" <<YML
criteria_ref: CRIT-001
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
"$REPO_GS" judge apply "$tmp/v1.yaml" >/dev/null && ok "judge apply pass with matching hashes"

# now change contract.yaml — verdict should become stale
yq e -i '.criteria[0].statement = "TAMPERED"' "$REPO/.goalspec/active/contract.yaml"
# new evidence hash if evidence changed (it didn't), but contract hash changed.
NEW_CHASH="$(cur_contract_hash)"
cat > "$tmp/v2.yaml" <<YML
criteria_ref: CRIT-001
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
if "$REPO_GS" judge apply "$tmp/v2.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted stale contract_hash"
else
  ok "judge apply rejected stale contract_hash"
fi

[ "$TESTS_FAIL" -eq 0 ]
