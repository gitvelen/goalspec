#!/usr/bin/env bash
# GOALC #80: scoped-reopen per-criterion freshness (B1). A reopen that touches
#            only some criteria (or weakens a cited evidence_requirement) must
#            NOT stale verdicts for untouched criteria. Closes the v0004
#            transcript's mass-re-judge → LOOP_CAPPED root cause.
#
# Contract: CRIT-1→ER-A, CRIT-2→ER-B, CRIT-FINAL→ER-A. Pass all, then reopen
# weakening ER-A's runtime_boundary (no criterion statement changed). After
# refreeze: CRIT-1 and CRIT-FINAL (which cite ER-A) must be stale; CRIT-2 (cites
# unchanged ER-B) must stay FRESH — proving both scoped freshness and the
# ER-content-drift guard (mod 1).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P80="$TESTS_TMP_ROOT/p80"; mkdir -p "$P80"
SF() { echo "$REPO/.goalspec/active/state.yaml"; }

pass_contract_review() {
  cat > "$P80/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$P80/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

fresh_initialized_repo goalc-80
"$REPO_GS" new-goal "scoped reopen" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-1
    kind: machine
    statement: behavior A observed
    evidence_requirement_refs: [ER-A]
  - id: CRIT-2
    kind: machine
    statement: behavior B observed
    evidence_requirement_refs: [ER-B]
  - id: CRIT-FINAL
    kind: machine
    final: true
    statement: final integration pass
    evidence_requirement_refs: [ER-A]
evidence_requirements:
  - id: ER-A
    runtime_boundary: integration
    statement: integration-level proof
  - id: ER-B
    runtime_boundary: unit
    statement: unit-level proof
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
pass_contract_review
"$REPO_GS" freeze >/dev/null

# Evidence + pass verdicts for all three (judge apply injects criterion_hash).
# Per-criterion evidence (realistic: chart evidence != whales evidence) so that
# re-stamping one evidence's contract_hash post-reopen does not invalidate
# another criterion's basis_hash.
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-1
    contract_hash: "$chash"
    criteria_refs: [CRIT-1, CRIT-FINAL]
    evidence_requirement_refs: [ER-A]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: integration
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: "2026-06-15T00:00:00Z"
    residual_risk: {level: none, notes: ""}
  - id: EV-2
    contract_hash: "$chash"
    criteria_refs: [CRIT-2]
    evidence_requirement_refs: [ER-B]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: unit
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: "2026-06-15T00:00:00Z"
    residual_risk: {level: none, notes: ""}
YML
ehash="$(cur_evidence_hash)"
apply_pass() {
  local c="$1" ref="$2"
  cat > "$P80/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [$ref]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "$c covered"
    evidence: [$ref]
    sufficiency: sufficient
    why: "$ref satisfies this criterion."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P80/v-$c.yaml" >/dev/null
}
apply_pass CRIT-1 EV-1
apply_pass CRIT-2 EV-2
apply_pass CRIT-FINAL EV-1
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content: {id: CAP-1, statement: x, status: active}
YML
"$REPO_GS" run >/dev/null 2>&1
[ "$(yq e '.status' "$(SF)")" = "ready_to_close" ] \
  && ok "all three pass pre-reopen (baseline)" \
  || bad "did not reach ready_to_close pre-reopen (status=$(yq e '.status' "$(SF)"))"

# Commit the run-loop business work before reopening (the worktree-clean freeze
# gate requires uncommitted business work to be committed; mirrors the real
# flow where run-loop output is committed before a reopen).
( cd "$REPO" && git add -A && git commit -q -m "run-loop work" ) >/dev/null

# Reopen: weaken ER-A's runtime_boundary ONLY (no criterion statement changed).
"$REPO_GS" reopen "weaken ER-A" >/dev/null
impact="$REPO/.goalspec/active/reopen-impact.yaml"
yq e -i '.analysis.summary = "Weaken ER-A runtime_boundary."' "$impact"
yq e -i '.analysis.criteria.modified = []' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"
yq e -i '(.evidence_requirements[] | select(.id == "ER-A") | .runtime_boundary) = "unit"' "$REPO/.goalspec/active/contract.yaml"
pass_contract_review
"$REPO_GS" freeze >/dev/null 2>"$P80/freeze2.err" || bad "scoped refreeze failed: $(cat "$P80/freeze2.err")"

# After refreeze: CRIT-1 + CRIT-FINAL (cite weakened ER-A) must be stale;
# CRIT-2 (cites unchanged ER-B) must stay FRESH.
"$REPO_GS" status >/tmp/goalspec-80-status.out 2>&1 || true
if grep -q 'UNMET_CRITERIA:.*CRIT-2' /tmp/goalspec-80-status.out; then
  bad "CRIT-2 staled despite its criterion/ER-B being untouched (scoped freshness broken)"
else
  ok "CRIT-2 stayed fresh across scoped reopen (B1 scoped freshness works)"
fi
if grep -q 'UNMET_CRITERIA:.*CRIT-1' /tmp/goalspec-80-status.out && grep -q 'UNMET_CRITERIA:.*CRIT-FINAL' /tmp/goalspec-80-status.out; then
  ok "CRIT-1 + CRIT-FINAL staled by ER-A weakening (mod 1: ER-content-drift guard works)"
else
  bad "ER-A weakening did not stale its citing criteria (CRIT-1/FINAL): $(grep UNMET /tmp/goalspec-80-status.out)"
fi

# Re-judge ONLY the stale criteria (CRIT-1, CRIT-FINAL); CRIT-2 needs no re-judge.
chash2="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
# refresh evidence contract_hash to the new contract so judge apply's evidence checks pass
yq e -i ".evidence[0].contract_hash = \"$chash2\"" "$REPO/.goalspec/active/evidence.yaml"
ehash2="$(cur_evidence_hash)"
for c in CRIT-1 CRIT-FINAL; do
  cat > "$P80/v2-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-1]
contract_hash: "$chash2"
evidence_hash: "$ehash2"
verdict: pass
reason: |
  Coverage audit:
  - claim: "$c re-covered"
    evidence: [EV-1]
    sufficiency: sufficient
    why: "EV-1 satisfies this criterion under the revised ER."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  "$REPO_GS" judge apply "$P80/v2-$c.yaml" >/dev/null
done

if "$REPO_GS" run >/tmp/goalspec-80-run2.out 2>&1 && grep -q 'CLOSE_PACKAGE_READY: true' /tmp/goalspec-80-run2.out; then
  ok "close package generated after re-judging only the stale criteria (CRIT-2 never re-judged)"
else
  bad "did not reach close package after scoped re-judge: $(grep -E 'CLOSE|UNMET|BLOCKER' /tmp/goalspec-80-run2.out | head -3)"
fi

[ "$TESTS_FAIL" -eq 0 ]
