#!/usr/bin/env bash
# GOALC #13: executor's evidence/trace self-claim "done" / "passed" must not let
#            state enter completed; only guardian verdict + complete can.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-13
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p13"; mkdir -p "$tmp"
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

# evidence claims "all passed" via summary text and exit_code 0, but no verdict.yaml entry.
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "self-test"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: executor
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: "all green, complete"}
YML

cat > "$REPO/.goalspec/active/trace.yaml" <<YML
traces:
  - id: TRACE-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    iteration: 1
    role: executor
    summary: "everything works, ready to complete"
    blockers: []
YML

cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      statement: x
      status: active
YML
"$REPO_GS" approve memory-patch >/dev/null

# state must NOT be completed.
status="$(yq e '.status' "$REPO/.goalspec/active/state.yaml")"
if [ "$status" = "completed" ]; then
  bad "state became completed from executor self-claim"
else
  ok "state not completed from executor self-claim (still $status)"
fi

if "$REPO_GS" complete >/dev/null 2>&1; then
  bad "complete succeeded without verdict"
else
  ok "complete refused without verdict"
fi

[ "$TESTS_FAIL" -eq 0 ]
