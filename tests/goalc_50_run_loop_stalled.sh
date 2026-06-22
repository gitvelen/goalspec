#!/usr/bin/env bash
# GOALC #50: run-loop no-progress detection (stalled) — the fourth stop condition.
# /goalspec run IS the loop. judge apply records a verdict fingerprint (every
# criterion's latest verdict) plus the evidence hash each round; if both are
# unchanged for stall_threshold consecutive rounds the loop is marked stalled.
# stalled != capped: capped = budget exhausted (close or raise); stalled = the
# loop is spinning on an unsolvable spec defect (reopen). Cases:
#   (1) repeated fail verdicts with unchanged evidence -> stalled
#   (2) a verdict change resets stall_count (normal iteration is not killed)
#   (3) evidence changes but verdicts don't -> grey zone, NOT stalled
#   (4) all-pass is exempt: stall_count may accumulate but stalled is not set,
#       and run still generates the close package
#   (5) reopen resets stall_count / fingerprint / outcome
#   (6) status surfaces stalled (-> reopen) distinctly from capped (-> close)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P50="$TESTS_TMP_ROOT/p50"; mkdir -p "$P50"
SF() { echo "$REPO/.goalspec/active/state.yaml"; }

pass_contract_review() {
  cat > "$P50/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$P50/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

write_3crit_contract() {
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
  local chash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-002, CRIT-FINAL-001]
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

write_memory_patch() {
  cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      statement: x
      status: active
YML
}

apply_pass() {
  local c="$1" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  cat > "$P50/v-pass.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
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
  "$REPO_GS" judge apply "$P50/v-pass.yaml"
}

apply_fail() {
  local c="$1" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  cat > "$P50/v-fail.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: fail
reason: not met
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P50/v-fail.yaml"
}

# === Case 1: repeated fail + unchanged evidence -> stalled ===
fresh_initialized_repo goalc-50-stall
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
# keep max_iterations high so the cap never fires first; stall_threshold=3.
yq e -i '.run_loop.max_iterations = 10' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.run_loop.stall_threshold = 3' "$REPO/.goalspec/project/profile.yaml"
write_evidence

apply_fail CRIT-001 >/dev/null        # round 1: fingerprint established, stall=0
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "0" ] && ok "round 1 stall_count=0" || bad "round 1 stall_count not 0"
apply_fail CRIT-001 >/dev/null        # round 2: fp+ehash unchanged -> stall=1
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "1" ] && ok "round 2 stall_count=1" || bad "round 2 stall_count not 1"
apply_fail CRIT-001 >/dev/null        # round 3: stall=2
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "2" ] && ok "round 3 stall_count=2" || bad "round 3 stall_count not 2"
apply_fail CRIT-001 >$P50/c1.out 2>&1 # round 4: stall=3 >= threshold -> stalled
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "3" ] && ok "round 4 stall_count=3" || bad "round 4 stall_count not 3"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "stalled" ] && ok "loop marked stalled at stall_threshold=3" || bad "last_outcome not stalled"
grep -q "LOOP_STALLED" $P50/c1.out && ok "LOOP_STALLED signal emitted" || bad "no LOOP_STALLED signal"

# stalled + unmet -> run refuses; deny reason mentions stalled.
if "$REPO_GS" run >$P50/c1run.out 2>&1; then
  bad "run allowed while stalled with unmet Criteria"
else
  ok "run refused while stalled with unmet Criteria"
fi
grep -qi "stalled" $P50/c1run.out && ok "run deny reason mentions stalled" || bad "run deny reason does not mention stalled"

# stalled -> further judge apply refused (no self-revival).
apply_fail CRIT-001 >$P50/c1j.out 2>&1 && bad "judge apply accepted while stalled" || ok "judge apply refused while stalled (no self-revival)"

# === Case 6: status surfaces stalled and steers toward reopen (same repo) ===
"$REPO_GS" status >$P50/c6stall.out 2>/dev/null
grep -qi "stalled" $P50/c6stall.out && ok "status surfaces stalled" || bad "status does not surface stalled"
grep -qi "reopen" $P50/c6stall.out && ok "status stalled action steers to reopen" || bad "status stalled action does not mention reopen"

# === Case 5: reopen resets stall_count / fingerprint / outcome ===
"$REPO_GS" reopen "spec is wrong" >/dev/null
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "0" ] && ok "reopen resets stall_count to 0" || bad "reopen did not reset stall_count"
[ "$(yq e '.run_loop.last_fingerprint' "$(SF)")" = "null" ] && ok "reopen clears last_fingerprint" || bad "reopen did not clear last_fingerprint"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "null" ] && ok "reopen clears last_outcome" || bad "reopen did not clear last_outcome"

# === Case 2: a verdict change resets stall_count (normal iteration not killed) ===
fresh_initialized_repo goalc-50-reset
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 10' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.run_loop.stall_threshold = 3' "$REPO/.goalspec/project/profile.yaml"
write_evidence

apply_fail CRIT-001 >/dev/null        # stall=0
apply_fail CRIT-001 >/dev/null        # stall=1 (unchanged)
apply_pass CRIT-001 >/dev/null        # verdict changed fail->pass -> stall resets to 0
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "0" ] && ok "verdict change resets stall_count to 0" || bad "verdict change did not reset stall_count"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" != "stalled" ] && ok "no stalled after a verdict change" || bad "stalled wrongly set after verdict change"

# === Case 3: evidence changes but verdicts don't -> grey zone, NOT stalled ===
fresh_initialized_repo goalc-50-grey
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 10' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.run_loop.stall_threshold = 2' "$REPO/.goalspec/project/profile.yaml"
write_evidence

apply_fail CRIT-001 >/dev/null        # stall=0, fp=A, ehash=E1
# change evidence (ehash -> E2) without changing any verdict
yq e -i '.evidence[0].produced_at = "2026-06-16T00:00:00Z"' "$REPO/.goalspec/active/evidence.yaml"
apply_fail CRIT-001 >/dev/null        # fp=A unchanged, ehash=E2 changed -> NOT stalled, stall=0
[ "$(yq e '.run_loop.stall_count' "$(SF)")" = "0" ] && ok "grey zone (evidence changed, verdicts not) keeps stall_count=0" || bad "grey zone wrongly incremented stall_count"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" != "stalled" ] && ok "grey zone not marked stalled" || bad "grey zone wrongly marked stalled"

# === Case 4: all-pass is exempt — stall_count may accumulate but stalled is not set ===
fresh_initialized_repo goalc-50-exempt
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 10' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.run_loop.stall_threshold = 3' "$REPO/.goalspec/project/profile.yaml"
write_evidence
write_memory_patch
apply_pass CRIT-001 >/dev/null        # all-pass path begins
apply_pass CRIT-002 >/dev/null
apply_pass CRIT-FINAL-001 >/dev/null  # now all required pass; fingerprint stable at all-pass
# repeat pass verdicts against an already-passing criterion: fingerprint + ehash
# unchanged, so stall_count climbs — but all-pass exempts the stalled marking.
apply_pass CRIT-001 >/dev/null        # stall=1
apply_pass CRIT-001 >/dev/null        # stall=2
apply_pass CRIT-001 >/dev/null        # stall=3 (>= threshold) but all-pass -> NOT stalled
[ "$(yq e '.run_loop.stall_count' "$(SF)" 2>/dev/null)" -ge 3 ] && ok "stall_count reached threshold under all-pass" || bad "stall_count did not reach threshold under all-pass"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" != "stalled" ] && ok "all-pass exempts the stalled marking" || bad "stalled wrongly set under all-pass"
# and run still generates the close package despite stall_count >= threshold.
if "$REPO_GS" run >$P50/c4.out 2>&1; then
  ok "run generates close package despite stall_count (all Criteria pass)"
else
  cat $P50/c4.out >&2
  bad "run refused despite all Criteria pass under stall exemption"
fi
[ "$(yq e '.status' "$(SF)")" = "ready_to_close" ] && ok "state advanced to ready_to_close under the stall exemption" || bad "state not ready_to_close"

[ "$TESTS_FAIL" -eq 0 ]
