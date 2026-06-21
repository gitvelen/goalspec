#!/usr/bin/env bash
# GOALC #17: with all required+final+hard criteria pass, no blocking questions,
#            scope-check pass, memory-patch approved -> complete succeeds.
# (This mirrors the smoke positive lifecycle as an explicit GOALC test.)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-17
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p17"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
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
EHASH="$(cur_evidence_hash)"

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
  ok "complete succeeds on all green path"
else
  bad "complete failed on all-green path"
fi

[ "$TESTS_FAIL" -eq 0 ]
