#!/usr/bin/env bash
# GOALC #14: judge apply must fail when verdict missing context:fresh / references
#            non-existent criteria/evidence / hash mismatch / pass verdict not citing
#            evidence satisfying evidence_requirement.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-14
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p14"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
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
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"

# A) missing context:fresh
cat > "$tmp/v-noctx.yaml" <<YML
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
context: stale
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/v-noctx.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted non-fresh context"
else
  ok "judge apply rejected non-fresh context"
fi

# B) criteria_ref not in contract
cat > "$tmp/v-badcrit.yaml" <<YML
criteria_ref: CRIT-DOES-NOT-EXIST
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
if "$REPO_GS" judge apply "$tmp/v-badcrit.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted unknown criteria_ref"
else
  ok "judge apply rejected unknown criteria_ref"
fi

# C) evidence_ref not in evidence.yaml
cat > "$tmp/v-badev.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-DOES-NOT-EXIST]
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
if "$REPO_GS" judge apply "$tmp/v-badev.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted unknown evidence_ref"
else
  ok "judge apply rejected unknown evidence_ref"
fi

# D) contract_hash mismatch
cat > "$tmp/v-badhash.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
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
if "$REPO_GS" judge apply "$tmp/v-badhash.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted mismatched contract_hash"
else
  ok "judge apply rejected mismatched contract_hash"
fi

# E) pass verdict without citing evidence that satisfies evidence_requirement_refs.
# Replace evidence with one that doesn't cite EVIDREQ-001.
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-002
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: []
    command: t
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: function
    persistence: memory
    completion_level: in_memory_domain
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH2="$(cur_evidence_hash)"
cat > "$tmp/v-noreq.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-002]
contract_hash: "$CHASH"
evidence_hash: "$EHASH2"
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
if "$REPO_GS" judge apply "$tmp/v-noreq.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted pass verdict without required evidence_requirement"
else
  ok "judge apply rejected pass verdict missing required evidence_requirement"
fi

[ "$TESTS_FAIL" -eq 0 ]
