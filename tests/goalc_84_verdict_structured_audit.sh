#!/usr/bin/env bash
# GOALC #84: a pass verdict may carry a structured `coverage_audit` field
#            (preferred) instead of the legacy free-text token reason. When
#            present, judge apply checks completeness — every claim binds >=1
#            evidence, and every cited evidence_ref appears in some claim. The
#            legacy token-reason form is still accepted (back-compat with
#            goalc_81/52, which use free-text reasons).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-84
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p84"; mkdir -p "$tmp"
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
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
  - id: EV-002
    contract_hash: "$chash"
    criteria_refs: [CRIT-001]
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
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"

# Case A: structured coverage_audit binding both evidence refs -> accepted.
cat > "$tmp/a.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001, EV-002]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
coverage_audit:
  - claim: "atomic claim one"
    evidence_refs: [EV-001]
    sufficiency: sufficient
    why: "EV-001 proves claim one"
  - claim: "atomic claim two"
    evidence_refs: [EV-002]
    sufficiency: sufficient
    why: "EV-002 proves claim two"
reason: "both claims covered"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/a.yaml" >/dev/null 2>&1; then
  ok "structured coverage_audit accepted when every evidence is bound to a claim"
else
  bad "structured coverage_audit rejected despite complete binding"
fi

# Case B: a claim with empty evidence_refs -> rejected (completeness).
cat > "$tmp/b.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
coverage_audit:
  - claim: "claim with no evidence"
    evidence_refs: []
    sufficiency: sufficient
    why: "hand-wavy"
reason: "x"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/b.yaml" >"$tmp/b.out" 2>"$tmp/b.err"; then
  bad "coverage_audit accepted a claim with empty evidence_refs"
else
  grep -q "no evidence_refs" "$tmp/b.err" && ok "claim with empty evidence_refs rejected" || bad "rejected but wrong reason: $(cat "$tmp/b.err")"
fi

# Case C: an evidence_ref not bound to any claim (orphan) -> rejected.
cat > "$tmp/c.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001, EV-002]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
coverage_audit:
  - claim: "only covers EV-001"
    evidence_refs: [EV-001]
    sufficiency: sufficient
    why: "EV-002 silently cited but never audited"
reason: "x"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/c.yaml" >"$tmp/c.out" 2>"$tmp/c.err"; then
  bad "coverage_audit accepted an evidence_ref not bound to any claim"
else
  grep -q "not bound to any coverage_audit claim" "$tmp/c.err" && ok "orphan evidence_ref rejected" || bad "rejected but wrong reason: $(cat "$tmp/c.err")"
fi

# Case D: legacy free-text token reason (no coverage_audit) still accepted.
cat > "$tmp/d.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "legacy token reason still works"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "back-compat with goalc_81/52"
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/d.yaml" >/dev/null 2>&1; then
  ok "legacy free-text token reason still accepted (back-compat)"
else
  bad "legacy token reason rejected by structured-audit change"
fi

# Case E: judge draft now emits a structured coverage_audit skeleton whose
# evidence_refs are pre-filled with the real cited refs (so the orphan check
# passes once claims are filled).
"$REPO_GS" judge draft CRIT-001 --verdict pass --evidence EV-001,EV-002 > "$tmp/draft.yaml" 2>"$tmp/draft.err"
if [ $? -ne 0 ]; then
  bad "E: judge draft failed: $(cat "$tmp/draft.err")"
else
  d_audit_len="$(yq e '.coverage_audit | length' "$tmp/draft.yaml" 2>/dev/null || echo 0)"
  d_claim_ev="$(yq e '.coverage_audit[0].evidence_refs | length' "$tmp/draft.yaml" 2>/dev/null || echo 0)"
  [ "${d_audit_len:-0}" -gt 0 ] && ok "draft emits a coverage_audit list" || bad "draft missing coverage_audit"
  [ "${d_claim_ev:-0}" -ge 2 ] && ok "draft coverage_audit pre-fills the real evidence_refs" || bad "draft coverage_audit evidence_refs not pre-filled (got $d_claim_ev)"
fi

[ "$TESTS_FAIL" -eq 0 ]
