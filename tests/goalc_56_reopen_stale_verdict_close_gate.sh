#!/usr/bin/env bash
# GOALC #56: after reopen + re-freeze, old pass verdicts/evidence from the
# previous contract must not satisfy the close gate.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-56
"$REPO_GS" new-goal "reopen stale verdict gate" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p56"; mkdir -p "$tmp"
cat > "$tmp/contract-v1.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract-v1.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

chash_v1="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash_v1"
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
ehash_v1="$(cur_evidence_hash)"
for c in CRIT-001 CRIT-FINAL-001; do
  cat > "$tmp/v1-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash_v1"
evidence_hash: "$ehash_v1"
verdict: pass
reason: |
  Coverage audit:
  - claim: "v1 criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the v1 contract only."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$tmp/v1-$c.yaml" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML

"$REPO_GS" reopen "tighten acceptance basis" >/dev/null
impact="$REPO/.goalspec/active/reopen-impact.yaml"
yq e -i '.analysis.summary = "Contract tightened; old verdicts must be rejudged."' "$impact"
yq e -i '.analysis.criteria.modified = ["CRIT-001", "CRIT-FINAL-001"]' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"
yq e -i '.criteria[0].statement = "behavior B observed after reopen"' "$REPO/.goalspec/active/contract.yaml"
cat > "$tmp/contract-v2.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract-v2.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

if "$REPO_GS" run >/tmp/goalspec-56-run.out 2>&1 && grep -q 'CLOSE_PACKAGE_READY: true' /tmp/goalspec-56-run.out; then
  bad "run generated a close package from stale v1 verdicts"
else
  ok "run does not close from stale v1 verdicts"
fi

if [ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "ready_to_close" ]; then
  bad "state advanced to ready_to_close with stale verdicts"
else
  ok "state stays out of ready_to_close"
fi

"$REPO_GS" status >/tmp/goalspec-56-status.out
grep -q 'UNMET_CRITERIA: .*CRIT-001' /tmp/goalspec-56-status.out \
  && ok "status reports stale CRIT-001 as unmet" \
  || bad "status hid stale CRIT-001"

chash_v2="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
cat > "$tmp/v2-stale-evidence.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash_v2"
evidence_hash: "$ehash_v1"
verdict: pass
reason: |
  Coverage audit:
  - claim: "v2 criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "This should be rejected because EV-001 belongs to v1."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/v2-stale-evidence.yaml" >/tmp/goalspec-56-judge.out 2>&1; then
  bad "judge accepted a fresh verdict citing stale evidence"
else
  grep -q 'stale evidence EV-001' /tmp/goalspec-56-judge.out \
    && ok "judge rejects fresh verdicts that cite stale evidence" \
    || bad "judge failed for an unexpected reason: $(cat /tmp/goalspec-56-judge.out)"
fi

"$REPO_GS" validate all >/tmp/goalspec-56-validate.out 2>&1 || true
grep -q 'stale or non-pass verdict' /tmp/goalspec-56-validate.out \
  && ok "validate reports stale completion verdicts" \
  || bad "validate did not report stale completion verdicts"

[ "$TESTS_FAIL" -eq 0 ]
