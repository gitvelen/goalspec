#!/usr/bin/env bash
# GOALC #83: opt-in coverage_claims + GOALSPEC_COVERED marker check. A pass
#            verdict on reproducible evidence that declares coverage_claims is
#            accepted only if the re-run output contains a marker per declared
#            route — closing the silent-pass gap where a test runs on the wrong
#            route yet exits 0. Evidence without coverage_claims is unaffected.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P83="$TESTS_TMP_ROOT/p83"; mkdir -p "$P83"

setup_frozen() {
  fresh_initialized_repo "goalc-83-$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal >/dev/null
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$P83/c.yaml"
  "$REPO_GS" review apply "$P83/c.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  "$REPO_GS" freeze >/dev/null
}

# write_evidence <command> <coverage_claims_yaml_block_or_EMPTY>
write_evidence() {
  local chash="$1" cmd="$2" cc="$3"
  mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
  if [ -n "$cc" ]; then
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
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
    coverage_claims:
$cc
YML
  else
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
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
  fi
}

apply_pass() {
  local chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  cat > "$P83/v.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "coverage marker criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P83/v.yaml" 2>"$P83/err.txt"
}

chash_of() { yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml"; }

# Case 1: coverage_claims + command emits the marker -> pass accepted.
setup_frozen ok
write_evidence "$(chash_of)" "echo 'GOALSPEC_COVERED: /governance/overview'" "      - route: /governance/overview"
if apply_pass >/dev/null; then ok "pass accepted when declared route has its marker"; else bad "pass rejected despite marker present: $(cat "$P83/err.txt")"; fi

# Case 2: coverage_claims + command exits 0 but emits NO marker -> rejected.
setup_frozen nomarker
write_evidence "$(chash_of)" "true" "      - route: /governance/overview"
if apply_pass >"$P83/out.txt" 2>&1; then
  bad "pass accepted when declared route marker was missing (silent-pass gap reopened)"
else
  grep -q "sensor coverage check failed" "$P83/err.txt" && ok "pass rejected; reason mentions sensor coverage check failed" || bad "rejected but wrong reason: $(cat "$P83/err.txt")"
  grep -q "/governance/overview" "$P83/err.txt" && ok "reason reports the missing route" || bad "reason missing the route name"
fi

# Case 3: multi-route — only one marker present -> rejected (the other missing).
setup_frozen multiroute
write_evidence "$(chash_of)" "echo 'GOALSPEC_COVERED: /a'" "$(printf '      - route: /a\n      - route: /b')"
if apply_pass >"$P83/out.txt" 2>&1; then
  bad "pass accepted with one of two declared routes missing its marker"
else
  grep -q "/b" "$P83/err.txt" && ok "multi-route: reason names the missing route" || bad "multi-route rejected but reason wrong: $(cat "$P83/err.txt")"
fi

# Case 4: no coverage_claims + exit 0 -> pass accepted (opt-in unchanged).
setup_frozen noclaims
write_evidence "$(chash_of)" "true" ""
if apply_pass >/dev/null; then ok "pass accepted without coverage_claims (opt-in, behavior unchanged)"; else bad "pass rejected without coverage_claims"; fi

# Case 5: evidence check rejects coverage_claims without reproducible:true.
setup_frozen norepro
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$(chash_of)"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    reproducible: false
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
    coverage_claims:
      - route: /governance/overview
YML
if "$REPO_GS" evidence check >"$P83/ec.txt" 2>&1; then
  bad "evidence check accepted coverage_claims without reproducible:true"
else
  grep -q "coverage_claims declared but reproducible != true" "$P83/ec.txt" && ok "evidence check flags coverage_claims without reproducible" || bad "evidence check rejected but wrong reason: $(cat "$P83/ec.txt")"
fi

# Case 6: evidence template documents the coverage_claims + marker convention.
setup_frozen tmpl
"$REPO_GS" evidence template CRIT-001 > "$P83/tpl.txt" 2>/dev/null
grep -q "coverage_claims" "$P83/tpl.txt" && grep -q "GOALSPEC_COVERED" "$P83/tpl.txt" \
  && ok "evidence template documents coverage_claims + marker convention" \
  || bad "evidence template missing coverage_claims/marker docs"

[ "$TESTS_FAIL" -eq 0 ]
