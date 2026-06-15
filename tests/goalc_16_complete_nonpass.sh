#!/usr/bin/env bash
# GOALC #16: any required criterion latest verdict = fail/insufficient/blocked/
#            stale/reopen_required -> complete fails with next action.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-16
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p16"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" next >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: executor
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"

# fail verdict on CRIT-001
cat > "$tmp/v-fail.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: not yet
context: fresh
judged_by: guardian
YML
"$REPO_GS" judge apply "$tmp/v-fail.yaml" >/dev/null

# add memory patch so it's the verdict that blocks
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
  bad "complete succeeded with fail verdict on required criterion"
else
  ok "complete blocked by non-pass verdict on required criterion"
fi

[ "$TESTS_FAIL" -eq 0 ]
