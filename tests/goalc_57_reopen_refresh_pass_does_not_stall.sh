#!/usr/bin/env bash
# GOALC #57: after reopen/refreeze, refreshing stale pass verdicts to fresh pass
# verdicts must count as progress. The stalled detector must not compare only
# verdict words, or old all-pass history can deadlock the run-loop before the
# remaining stale criteria are rejudged.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P57="$TESTS_TMP_ROOT/p57"; mkdir -p "$P57"
SF() { echo "$REPO/.goalspec/active/state.yaml"; }

pass_contract_review() {
  cat > "$P57/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$P57/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

write_4crit_contract() {
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    required_for_completion: true
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-002
    kind: machine
    priority: P0
    required_for_completion: true
    statement: behavior B observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-003
    kind: machine
    priority: P0
    required_for_completion: true
    statement: behavior C observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    required_for_completion: true
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
}

write_evidence() {
  local chash="$1" produced_at="$2"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-002, CRIT-003, CRIT-FINAL-001]
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
    produced_at: $produced_at
    residual_risk: {level: none, notes: ""}
YML
}

apply_pass() {
  local c="$1" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  cat > "$P57/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "$c observed"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P57/v-$c.yaml"
}

fresh_initialized_repo goalc-57-refresh
"$REPO_GS" new-goal "reopen refresh pass should progress" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_4crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 20' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.run_loop.stall_threshold = 2' "$REPO/.goalspec/project/profile.yaml"

chash_v1="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
write_evidence "$chash_v1" "2026-06-15T00:00:00Z"
for c in CRIT-001 CRIT-002 CRIT-003 CRIT-FINAL-001; do
  apply_pass "$c" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML
"$REPO_GS" run >/dev/null
[ "$(yq e '.status' "$(SF)")" = "ready_to_close" ] && ok "v1 reaches ready_to_close" || bad "v1 not ready_to_close"

"$REPO_GS" reopen "tighten acceptance basis" >/dev/null
impact="$REPO/.goalspec/active/reopen-impact.yaml"
yq e -i '.analysis.summary = "Contract tightened; existing pass verdicts must be refreshed."' "$impact"
yq e -i '.analysis.criteria.modified = ["CRIT-001", "CRIT-002", "CRIT-003", "CRIT-FINAL-001"]' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"
yq e -i '.criteria[0].statement = "behavior A observed after reopen"' "$REPO/.goalspec/active/contract.yaml"
pass_contract_review
"$REPO_GS" freeze >/dev/null

chash_v2="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
write_evidence "$chash_v2" "2026-06-16T00:00:00Z"

apply_pass CRIT-001 >/dev/null
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "0" ] && ok "fresh CRIT-001 resets stall_count" || bad "CRIT-001 did not reset stall_count"
apply_pass CRIT-002 >/dev/null
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" != "stalled" ] && ok "fresh CRIT-002 does not stall" || bad "stalled after CRIT-002"
apply_pass CRIT-003 >/dev/null
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" != "stalled" ] && ok "fresh CRIT-003 does not stall" || bad "stalled after CRIT-003"

"$REPO_GS" status >"$P57/status-partial.out"
grep -q 'UNMET_CRITERIA: .*CRIT-FINAL-001' "$P57/status-partial.out" \
  && ok "status still reports the remaining stale criterion" \
  || bad "status did not report CRIT-FINAL-001 as unmet"
grep -qi 'Run-loop stalled' "$P57/status-partial.out" \
  && bad "status reported a false stalled state" \
  || ok "status does not report false stalled state"

apply_pass CRIT-FINAL-001 >/dev/null
"$REPO_GS" run >"$P57/run-close.out" 2>&1
grep -q 'CLOSE_PACKAGE_READY: true' "$P57/run-close.out" \
  && ok "run generates close package after all refreshed passes" \
  || bad "run did not generate close package"

# Legacy recovery: an old-format stalled fingerprint must not permanently block
# judge apply when the current richer fingerprint differs.
"$REPO_GS" reopen "legacy stalled recovery" >/dev/null
yq e -i '.analysis.summary = "Reopen again to verify legacy stalled recovery."' "$impact"
yq e -i '.analysis.criteria.modified = ["CRIT-001"]' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"
yq e -i '.criteria[0].statement = "behavior A observed after legacy recovery"' "$REPO/.goalspec/active/contract.yaml"
pass_contract_review
"$REPO_GS" freeze >/dev/null
chash_v3="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
write_evidence "$chash_v3" "2026-06-17T00:00:00Z"
EHASH="$(cur_evidence_hash)" yq e -i '.run_loop.last_outcome = "stalled" | .run_loop.stall_count = 2 | .run_loop.last_fingerprint = "CRIT-001=pass|CRIT-002=pass|CRIT-003=pass|CRIT-FINAL-001=pass|" | .run_loop.last_evidence_hash = strenv(EHASH)' "$(SF)"
if apply_pass CRIT-001 >"$P57/legacy-judge.out" 2>&1; then
  ok "judge apply recovers from obsolete legacy stalled fingerprint"
else
  cat "$P57/legacy-judge.out" >&2
  bad "judge apply stayed blocked by obsolete legacy stalled fingerprint"
fi

[ "$TESTS_FAIL" -eq 0 ]
