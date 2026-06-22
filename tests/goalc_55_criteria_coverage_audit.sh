#!/usr/bin/env bash
# GOALC #55: Master verdicts must carry Criteria Coverage Audit discipline.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-55-coverage-audit
"$REPO_GS" new-goal "test coverage audit" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p55"; mkdir -p "$tmp"
cat > "$tmp/contract-review.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract-review.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

prompt="$($REPO_GS judge prompt CRIT-001)"
printf '%s\n' "$prompt" | grep -q 'Criteria Coverage Audit' \
  && printf '%s\n' "$prompt" | grep -q 'Statement decomposition' \
  && printf '%s\n' "$prompt" | grep -q 'Evidence mapping' \
  && printf '%s\n' "$prompt" | grep -q 'Evidence strength classification' \
  && printf '%s\n' "$prompt" | grep -q 'Sufficiency check' \
  && printf '%s\n' "$prompt" | grep -q 'if any atomic claim lacks sufficient evidence, do not pass' \
  && ok "judge prompt requires Criteria Coverage Audit" \
  || bad "judge prompt missing Criteria Coverage Audit discipline"

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
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
EHASH="$(cur_evidence_hash)"

cat > "$tmp/v-no-audit.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: "tests pass"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/v-no-audit.yaml" >/dev/null 2>"$tmp/no-audit.err"; then
  bad "judge apply accepted pass without coverage audit"
else
  grep -q 'Criteria Coverage Audit' "$tmp/no-audit.err" \
    && ok "judge apply rejects pass without coverage audit" \
    || bad "coverage-audit rejection did not explain missing audit"
fi

cat > "$tmp/v-with-audit.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "behavior A observed"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 is browser-bound evidence satisfying EVIDREQ-001 for the test criterion."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/v-with-audit.yaml" >/dev/null 2>"$tmp/with-audit.err"; then
  ok "judge apply accepts pass with coverage audit"
else
  bad "judge apply rejected pass with coverage audit: $(cat "$tmp/with-audit.err")"
fi

[ "$TESTS_FAIL" -eq 0 ]
