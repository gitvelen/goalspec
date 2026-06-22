#!/usr/bin/env bash
# GOALC #51: trace.yaml is live + run_loop.trajectory is derived (Loop Engineering
# observability — Tier 1). Each judge-apply round appends a trace entry and
# recomputes the tried/failed/blocker/next summary.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P51="$TESTS_TMP_ROOT/p51"; mkdir -p "$P51"
SF() { echo "$REPO/.goalspec/active/state.yaml"; }
TF() { echo "$REPO/.goalspec/active/trace.yaml"; }

setup_frozen() {
  fresh_initialized_repo "goalc-51-$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal >/dev/null
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$P51/c.yaml"
  "$REPO_GS" review apply "$P51/c.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  "$REPO_GS" freeze >/dev/null
}

write_ev() {
  local chash="$1"
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
}

apply_v() {  # <crit> <verdict> <reason>
  local c="$1" v="$2" r="$3" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  if [ "$v" = "pass" ]; then
    cat > "$P51/v.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: $v
reason: |
  Coverage audit:
  - claim: "$r"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  else
    cat > "$P51/v.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: $v
reason: "$r"
context: fresh
evaluated_by: master
YML
  fi
  "$REPO_GS" judge apply "$P51/v.yaml"
}

# === Case 1: one fail round -> trace entry + derived trajectory ===
setup_frozen failcase
write_ev "$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
apply_v CRIT-001 fail "not yet observed" >/dev/null
[ "$(yq e '.traces | length' "$(TF)")" = "1" ] && ok "trace has 1 entry after 1 round" || bad "trace length != 1"
[ "$(yq e '.traces[0].verdict' "$(TF)")" = "fail" ] && ok "trace[0].verdict=fail" || bad "trace[0].verdict"
[ "$(yq e '.traces[0].criterion_ref' "$(TF)")" = "CRIT-001" ] && ok "trace[0].criterion_ref" || bad "trace[0].criterion_ref"
[ "$(yq e '.traces[0].stop_check.outcome' "$(TF)")" = "continue" ] && ok "trace[0] outcome=continue" || bad "trace[0] outcome"
yq e '.run_loop.trajectory.failed_approaches[]' "$(SF)" | grep -qx "CRIT-001=fail" \
  && ok "trajectory.failed_approaches has CRIT-001=fail" || bad "trajectory missing failed approach"
yq e '.run_loop.trajectory.current_blocker' "$(SF)" | grep -q "CRIT-001" \
  && ok "current_blocker reflects the failing criterion" || bad "current_blocker not set"
yq e '.run_loop.trajectory.next_step' "$(SF)" | grep -q "CRIT-001" \
  && ok "next_step points at the non-pass criterion" || bad "next_step not set"
# provenance: trace records the frozen basis it ran under
[ -n "$(yq e '.traces[0].contract_hash' "$(TF)")" ] && ok "trace records contract_hash provenance" || bad "no contract_hash"
[ -n "$(yq e '.traces[0].prompt_hash' "$(TF)")" ] && ok "trace records prompt_hash provenance" || bad "no prompt_hash"

# reopen clears trajectory but keeps trace (the audit trail survives).
"$REPO_GS" reopen "revise" >/dev/null
[ "$(yq e '.run_loop.trajectory.failed_approaches | length' "$(SF)")" = "0" ] && ok "reopen clears trajectory" || bad "reopen did not clear trajectory"
[ "$(yq e '.run_loop.trajectory.current_blocker' "$(SF)")" = "" ] && ok "reopen clears current_blocker" || bad "reopen did not clear blocker"
[ "$(yq e '.traces | length' "$(TF)")" = "1" ] && ok "reopen keeps trace (audit trail)" || bad "reopen wiped trace"

# === Case 2: iteration cap -> trace entry outcome=capped ===
setup_frozen capcase
yq e -i '.run_loop.max_iterations = 2' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
apply_v CRIT-001 fail "x" >/dev/null
apply_v CRIT-FINAL-001 fail "x" >/dev/null   # iteration 2 -> capped
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "capped" ] && ok "loop marked capped at max_iterations=2" || bad "not capped"
[ "$(yq e '.traces[-1].stop_check.outcome' "$(TF)")" = "capped" ] && ok "trace last entry outcome=capped" || bad "trace outcome not capped"
yq e '.traces[-1].stop_check.why' "$(TF)" | grep -q "max_iterations=2" \
  && ok "trace cap why mentions max_iterations=2" || bad "trace cap why missing threshold"

# === Case 3: no-progress stall -> trace entry outcome=stalled ===
setup_frozen stallcase
yq e -i '.run_loop.stall_threshold = 2' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
apply_v CRIT-001 fail "no change" >/dev/null   # round 1: stall_count 0
apply_v CRIT-001 fail "no change" >/dev/null   # round 2: stall_count 1
apply_v CRIT-001 fail "no change" >/dev/null   # round 3: stall_count 2 -> stalled
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "stalled" ] && ok "loop marked stalled at stall_threshold=2" || bad "not stalled"
[ "$(yq e '.traces[-1].stop_check.outcome' "$(TF)")" = "stalled" ] && ok "trace last entry outcome=stalled" || bad "trace outcome not stalled"

# === Case 4: all-pass -> trajectory clears blocker, no failed approaches ===
setup_frozen allpass
write_ev "$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
apply_v CRIT-001 pass "ok" >/dev/null
apply_v CRIT-FINAL-001 pass "ok" >/dev/null
[ "$(yq e '.run_loop.trajectory.failed_approaches | length' "$(SF)")" = "0" ] && ok "all-pass: no failed_approaches" || bad "failed_approaches non-empty"
[ "$(yq e '.run_loop.trajectory.current_blocker' "$(SF)")" = "" ] && ok "all-pass: blocker cleared" || bad "blocker not cleared"
yq e '.run_loop.trajectory.tried_paths[]' "$(SF)" | grep -qx "CRIT-001=pass" \
  && ok "all-pass: tried_paths records the pass" || bad "tried_paths missing pass"

[ "$TESTS_FAIL" -eq 0 ]
