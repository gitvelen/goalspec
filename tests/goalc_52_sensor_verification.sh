#!/usr/bin/env bash
# GOALC #52: sensor verification (Tier 2). A pass verdict on reproducible evidence
# must be confirmable by re-running the evidence's command at judge-apply time —
# not just by trusting the Subagent's recorded exit_code. Profile test/lint/
# typecheck only run at close; this closes the self-claim gap mid-loop.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P52="$TESTS_TMP_ROOT/p52"; mkdir -p "$P52"

setup_frozen() {
  fresh_initialized_repo "goalc-52-$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal >/dev/null
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$P52/c.yaml"
  "$REPO_GS" review apply "$P52/c.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  "$REPO_GS" freeze >/dev/null
}

# write_evidence <command> <reproducible>
write_evidence() {
  local chash="$1" cmd="$2" repro="$3"
  mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "$cmd"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: $repro
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
}

# apply <crit> <verdict>  (reason is fixed)
apply_v() {
  local c="$1" v="$2" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  cat > "$P52/v.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: $v
reason: ok
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P52/v.yaml" 2>"$P52/err.txt"
}

chash_of() { yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml"; }

# Case 1: reproducible + command "true" + pass -> accepted (sensor re-run exits 0).
setup_frozen ok
write_evidence "$(chash_of)" "true" true
if apply_v CRIT-001 pass >/dev/null; then ok "pass accepted when reproducible command exits 0"; else bad "pass rejected despite reproducible:true + true"; fi

# Case 2: reproducible + command "false" + pass -> rejected (sensor exited 1).
setup_frozen badcmd
write_evidence "$(chash_of)" "false" true
if apply_v CRIT-001 pass >"$P52/out.txt" 2>&1; then
  bad "pass accepted when reproducible command exits non-zero"
else
  grep -q "sensor verification failed" "$P52/err.txt" && ok "pass rejected; reason mentions sensor verification failed" || bad "rejected but reason lacks sensor mention"
  grep -q "exited 1" "$P52/err.txt" && ok "reason reports the actual exit code" || bad "reason missing exit code"
fi

# Case 3: reproducible: false + pass -> accepted (never re-run; side-effect safety).
setup_frozen norepro
write_evidence "$(chash_of)" "definitely-not-a-real-command" false
if apply_v CRIT-001 pass >/dev/null; then ok "pass accepted when reproducible:false (no re-run)"; else bad "pass rejected despite reproducible:false"; fi

# Case 4: fail verdict + reproducible:true command "false" -> accepted (sensor
# only runs inside the pass branch; negative verdicts never trigger a re-run).
setup_frozen failpath
write_evidence "$(chash_of)" "false" true
if apply_v CRIT-001 fail >/dev/null; then ok "fail verdict accepted; sensor skipped on non-pass"; else bad "fail verdict rejected by sensor"; fi

# Case 5: evidence check flags reproducible:true with an empty command.
setup_frozen emptycmd
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$(chash_of)"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: ""
    exit_code: 0
    artifact_paths: []
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
if "$REPO_GS" evidence check >"$P52/ec.txt" 2>&1; then
  bad "evidence check accepted reproducible:true with empty command"
else
  grep -q "reproducible=true requires a non-empty command" "$P52/ec.txt" && ok "evidence check flags empty command on reproducible evidence" || bad "evidence check did not flag empty command"
fi

[ "$TESTS_FAIL" -eq 0 ]
