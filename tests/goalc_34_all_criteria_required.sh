#!/usr/bin/env bash
# GOALC #34: criteria are required by default — a criterion without any
#            required_for_completion/final/P0 flag must still block completion
#            when it has no pass verdict.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-34
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null

# CRIT-002 has no priority/required_for_completion/final flags. Under the old
# filter it was skipped; under "required by default" it must block completion.
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-002
    statement: behavior B observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    priority: P0
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
tmp="$TESTS_TMP_ROOT/p34"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001, CRIT-002]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
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

# judge the flagged criteria pass, but LEAVE CRIT-002 (no flags) unjudged
for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
done

cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      statement: x
      status: active
YML
"$REPO_GS" approve memory-patch >/dev/null

if "$REPO_GS" complete >/dev/null 2>&1; then
  bad "complete succeeded with CRIT-002 (no flags) unjudged"
else
  ok "complete blocked: unflagged criterion without verdict is required"
fi

[ "$TESTS_FAIL" -eq 0 ]
