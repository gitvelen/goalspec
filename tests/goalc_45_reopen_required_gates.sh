#!/usr/bin/env bash
# GOALC #45: reopen_required is a hard recovery gate. While the frozen contract
#            is being re-reviewed, run/judge/complete/close must all refuse to
#            advance the lifecycle until the goal/contract is re-reviewed,
#            re-approved, and frozen again.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-45
"$REPO_GS" new-goal "test reopen gate" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p45"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

# Make the goal completion-ready so complete/close would otherwise be reachable.
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$(yq e '.contract_hash' "$REPO/.goalspec/active/state.yaml")"
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
    produced_at: now
    residual_risk:
      level: none
      notes: ""
YML
EHASH="$(cur_evidence_hash)"
FROZEN_CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/state.yaml")"
for crit in CRIT-001 CRIT-FINAL-001; do
  cat > "$tmp/v-$crit.yaml" <<YML
criteria_ref: $crit
evidence_refs: [EV-001]
contract_hash: "$FROZEN_CHASH"
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
  "$REPO_GS" judge apply "$tmp/v-$crit.yaml" >/dev/null || bad "setup: judge apply failed for $crit"
done
"$REPO_GS" complete >/dev/null || bad "setup: complete should succeed before reopen"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "ready_to_close" ] || bad "setup: expected ready_to_close"

"$REPO_GS" reopen "criteria missing scenario" >/dev/null
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "reopen_required" ] \
  && ok "reopen enters reopen_required" \
  || bad "reopen did not enter reopen_required"

if "$REPO_GS" run >/tmp/goalspec-run45.out 2>&1; then
  bad "run succeeded during reopen_required"
else
  grep -q 'reopen_required' /tmp/goalspec-run45.out && ok "run blocked by reopen_required" \
    || bad "run block did not mention reopen_required"
fi

cat > "$tmp/v-again.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$(cur_contract_hash)"
evidence_hash: "$(cur_evidence_hash)"
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
if "$REPO_GS" judge apply "$tmp/v-again.yaml" >/tmp/goalspec-judge45.out 2>&1; then
  bad "judge apply succeeded during reopen_required"
else
  grep -q 'reopen_required' /tmp/goalspec-judge45.out && ok "judge apply blocked by reopen_required" \
    || bad "judge apply block did not mention reopen_required"
fi

if "$REPO_GS" complete >/tmp/goalspec-complete45.out 2>&1; then
  bad "complete succeeded during reopen_required"
else
  grep -q 'reopen_required' /tmp/goalspec-complete45.out && ok "complete blocked by reopen_required" \
    || bad "complete block did not mention reopen_required"
fi

if "$REPO_GS" close >/tmp/goalspec-close45.out 2>&1; then
  bad "close succeeded during reopen_required"
else
  grep -q 'reopen_required' /tmp/goalspec-close45.out && ok "close blocked by reopen_required" \
    || bad "close block did not mention reopen_required"
fi

[ "$TESTS_FAIL" -eq 0 ]
