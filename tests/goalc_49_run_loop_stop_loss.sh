#!/usr/bin/env bash
# GOALC #49: run-loop stop-loss + machine/judgment Criteria 分流.
# /goalspec run IS the loop (the Goal-Driven Prompt loops until Criteria pass).
# These cases cover the two stop conditions injected into that loop:
#   (1) criteria kind enum validation (machine|judgment)
#   (2) judge-apply iteration cap (token stop-loss), capped blocks run/judge,
#       but exempts the all-pass case so close can still proceed
#   (3) judgment-kind criteria gate the loop once machine criteria pass
#   (4) reopen resets the counter
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P49="$TESTS_TMP_ROOT/p49"; mkdir -p "$P49"
SF() { echo "$REPO/.goalspec/active/state.yaml"; }

pass_contract_review() {
  cat > "$P49/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$P49/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

write_evidence() {
  local chash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-002, CRIT-J-001, CRIT-FINAL-001]
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
  cat > "$P49/v-$c.yaml" <<YML
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
  "$REPO_GS" judge apply "$P49/v-$c.yaml"
}

# 3 machine criteria + final.
write_3crit_contract() {
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-002
    kind: machine
    statement: behavior B observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
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

# 2 machine + 1 judgment + final.
write_judgment_contract() {
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-J-001
    kind: judgment
    statement: the UX flow is acceptable to a human reviewer
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
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

# === Case 1: kind enum — bogus kind blocks freeze ===
fresh_initialized_repo goalc-49-kind
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: bogus
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
pass_contract_review
if "$REPO_GS" freeze >$P49/goalc49k.err 2>&1; then
  bad "freeze accepted invalid kind 'bogus'"
else
  grep -q "invalid kind" $P49/goalc49k.err && ok "freeze blocked on invalid kind" || bad "freeze blocked but not for kind"
fi

# === Case 2-3,6: iteration cap blocks the loop; reopen resets ===
fresh_initialized_repo goalc-49-cap
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 2' "$REPO/.goalspec/project/profile.yaml"
write_evidence

apply_pass CRIT-001 >/dev/null
[ "$(yq e '.run_loop.iteration' "$(SF)")" = "1" ] \
  && ok "judge apply increments run_loop.iteration to 1" \
  || bad "iteration not 1 after first verdict"

# 2nd verdict hits the cap; CRIT-FINAL-001 still unjudged -> not all pass.
apply_pass CRIT-002 >$P49/goalc49cap.out 2>&1
[ "$(yq e '.run_loop.iteration' "$(SF)")" = "2" ] && ok "iteration is 2 after second verdict" || bad "iteration not 2"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "capped" ] \
  && ok "loop marked capped at max_iterations=2" || bad "last_outcome not capped"
grep -q "LOOP_CAPPED" $P49/goalc49cap.out && ok "LOOP_CAPPED signal emitted" || bad "no LOOP_CAPPED signal"

# capped + unmet -> run refuses; status surfaces the cap.
if "$REPO_GS" run >$P49/goalc49run.out 2>&1; then
  bad "run allowed while capped with unmet Criteria"
else
  ok "run refused while capped with unmet Criteria"
fi
grep -qi "capped" $P49/goalc49run.out && ok "run deny reason mentions capped" || bad "run deny reason does not mention capped"
"$REPO_GS" status 2>/dev/null | grep -q "iteration cap" \
  && ok "status NEXT_USER_ACTION surfaces the cap" || bad "status does not surface cap"

# capped -> further judge apply refused (no self-revival).
apply_pass CRIT-001 >$P49/goalc49j2.out 2>&1 && bad "judge apply accepted while capped" || ok "judge apply refused while capped (no self-revival)"

# reopen resets the counter.
"$REPO_GS" reopen "spec needs revision" >/dev/null
[ "$(yq e '.run_loop.iteration' "$(SF)")" = "0" ] && ok "reopen resets iteration to 0" || bad "reopen did not reset iteration"
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "null" ] && ok "reopen clears last_outcome" || bad "reopen did not clear last_outcome"

# === Case 4: cap exempts all-pass -> run still generates close package ===
fresh_initialized_repo goalc-49-exempt
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_3crit_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
yq e -i '.run_loop.max_iterations = 3' "$REPO/.goalspec/project/profile.yaml"
write_evidence
write_memory_patch
apply_pass CRIT-001 >/dev/null        # iter 1
apply_pass CRIT-002 >/dev/null        # iter 2
apply_pass CRIT-FINAL-001 >/dev/null  # iter 3 -> capped, but all pass now
[ "$(yq e '.run_loop.last_outcome' "$(SF)")" = "capped" ] && ok "capped at the final verdict" || bad "not capped at final verdict"
if "$REPO_GS" run >$P49/goalc49er.out 2>&1; then
  ok "run generates close package despite cap (all Criteria pass)"
else
  cat $P49/goalc49er.out >&2
  bad "run refused despite all Criteria pass under cap"
fi
[ "$(yq e '.status' "$(SF)")" = "ready_to_close" ] && ok "state advanced to ready_to_close under the cap exemption" || bad "state not ready_to_close"

# === Case 5: judgment criteria gate the loop once machine criteria pass ===
fresh_initialized_repo goalc-49-judg
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal >/dev/null
"$REPO_GS" compile >/dev/null
write_judgment_contract
pass_contract_review
"$REPO_GS" freeze >/dev/null
write_evidence
write_memory_patch
apply_pass CRIT-001 >/dev/null       # machine
apply_pass CRIT-FINAL-001 >/dev/null # machine final
# machine criteria pass, judgment CRIT-J-001 unmet -> run refuses.
if "$REPO_GS" run >$P49/goalc49j.out 2>&1; then
  bad "run allowed with unmet judgment criterion"
else
  ok "run refused with unmet judgment criterion"
fi
grep -qi "judgment" $P49/goalc49j.out && ok "run deny reason mentions judgment" || bad "run deny reason does not mention judgment"
# once the judgment criterion passes, run proceeds.
apply_pass CRIT-J-001 >/dev/null
if "$REPO_GS" run >$P49/goalc49j2.out 2>&1; then
  ok "run allowed after judgment criterion passes"
else
  cat $P49/goalc49j2.out >&2
  bad "run refused after judgment criterion passed"
fi

[ "$TESTS_FAIL" -eq 0 ]
