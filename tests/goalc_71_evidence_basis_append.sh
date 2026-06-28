#!/usr/bin/env bash
# GOALC #71: appending unrelated evidence must not stale existing pass verdicts.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-71
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p71"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" run >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"
echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
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
EHASH="$(cur_evidence_hash)"
for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
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
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null || bad "setup judge apply failed for $c"
done

if yq e '.verdicts[0].evidence_basis_hash // ""' "$REPO/.goalspec/active/verdict.yaml" | grep -q '^sha256:'; then
  ok "judge apply stores evidence_basis_hash"
else
  bad "judge apply did not store evidence_basis_hash"
fi

cat >> "$REPO/.goalspec/active/evidence.yaml" <<YML
  - id: EV-999
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-OTHER]
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
    produced_at: 2026-06-15T00:00:01Z
    residual_risk: {level: none, notes: ""}
YML
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML

status_out="$($REPO_GS status)"
echo "$status_out" | grep -q '^UNMET_CRITERIA: (none)' \
  && ok "unrelated evidence append does not stale pass verdicts" \
  || bad "unrelated evidence append staled pass verdicts: $status_out"

run_out="$($REPO_GS run 2>&1)"
echo "$run_out" | grep -q 'CLOSE_PACKAGE_READY: true' \
  && ok "run generates close package after unrelated evidence append" \
  || bad "run did not generate close package after unrelated evidence append: $run_out"

# Mutating cited evidence must still stale the verdict basis.
yq e -i '(.evidence[] | select(.id == "EV-001") | .command) = "false"' "$REPO/.goalspec/active/evidence.yaml"
yq e -i '.status = "running"' "$REPO/.goalspec/active/state.yaml"
status_out="$($REPO_GS status)"
echo "$status_out" | grep -q 'stale_evidence_basis' \
  && ok "mutating cited evidence stales verdict basis" \
  || bad "mutating cited evidence did not stale verdict basis: $status_out"

[ "$TESTS_FAIL" -eq 0 ]
