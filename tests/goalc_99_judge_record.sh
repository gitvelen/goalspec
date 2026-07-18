#!/usr/bin/env bash
# GOALC #99: judge record — one-shot verdict assembly + apply. The AI supplies
#            crit/verdict/evidence/reason on the CLI; record builds a hash-correct
#            verdict YAML and runs apply, so no verdict YAML is ever hand-written
#            (the source of field-corruption / hash-misalignment rework). pass
#            requires --coverage-claim — record does NOT auto-fabricate a placeholder
#            claim, preserving v0008's structured coverage_audit intent.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-99
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p99"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"

cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
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
  - id: EV-002
    contract_hash: "$chash"
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
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"

# Case A: record insufficient — main use case (no coverage_audit needed).
if "$REPO_GS" judge record CRIT-001 --evidence EV-001 --verdict insufficient --reason "awaiting runtime evidence" >"$tmp/a.out" 2>"$tmp/a.err"; then
  grep -q "verdict applied: insufficient (crit=CRIT-001)" "$tmp/a.out" && ok "record insufficient applies in one shot" || bad "record insufficient unexpected output: $(cat "$tmp/a.out")"
else
  bad "record insufficient failed: $(cat "$tmp/a.err")"
fi

# Case B: record pass WITH --coverage-claim — accepted, claim carried through.
if "$REPO_GS" judge record CRIT-001 --evidence EV-001,EV-002 --verdict pass --reason "both cover the behavior" --coverage-claim "CRIT-001 behavior A observed end-to-end" >"$tmp/b.out" 2>"$tmp/b.err"; then
  grep -q "verdict applied: pass (crit=CRIT-001)" "$tmp/b.out" && ok "record pass with --coverage-claim applies" || bad "record pass unexpected output: $(cat "$tmp/b.out")"
else
  bad "record pass with --coverage-claim failed: $(cat "$tmp/b.err")"
fi

# Case C: record pass WITHOUT --coverage-claim — rejected (no auto-fabricated claim).
if "$REPO_GS" judge record CRIT-001 --evidence EV-001 --verdict pass --reason "x" >"$tmp/c.out" 2>"$tmp/c.err"; then
  bad "record pass without --coverage-claim was accepted (should require a real claim)"
else
  grep -q "requires --coverage-claim" "$tmp/c.err" && ok "record pass without --coverage-claim rejected" || bad "record pass rejected but wrong reason: $(cat "$tmp/c.err")"
fi

# Case D: record unknown criteria — rejected.
if "$REPO_GS" judge record CRIT-NOPE --evidence EV-001 --verdict insufficient --reason "x" >"$tmp/d.out" 2>"$tmp/d.err"; then
  bad "record accepted unknown criteria"
else
  grep -q "criteria_ref CRIT-NOPE not found" "$tmp/d.err" && ok "record unknown criteria rejected" || bad "record unknown criteria rejected wrong: $(cat "$tmp/d.err")"
fi

# Case E: record unknown evidence — rejected.
if "$REPO_GS" judge record CRIT-001 --evidence EV-NOPE --verdict insufficient --reason "x" >"$tmp/e.out" 2>"$tmp/e.err"; then
  bad "record accepted unknown evidence"
else
  grep -q "evidence_ref EV-NOPE not found" "$tmp/e.err" && ok "record unknown evidence rejected" || bad "record unknown evidence rejected wrong: $(cat "$tmp/e.err")"
fi

# Case F: record pass verdict carries the REAL coverage_audit claim into verdict.yaml
#         (not a placeholder) — queryable downstream.
last_audit="$(yq e '.verdicts[-1].coverage_audit[0].claim' "$REPO/.goalspec/active/verdict.yaml" 2>/dev/null)"
[ "$last_audit" = "CRIT-001 behavior A observed end-to-end" ] && ok "record pass verdict stores the real coverage claim" || bad "record pass verdict claim not stored (got: $last_audit)"

[ "$TESTS_FAIL" -eq 0 ]
