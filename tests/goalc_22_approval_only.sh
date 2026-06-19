#!/usr/bin/env bash
# GOALC #22: human approval only for goal / contract / memory-patch / high-risk /
#            regression-waiver; approval cannot turn a fail verdict into pass.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-22
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p22"; mkdir -p "$tmp"
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

# Fail verdict on CRIT-001.
cat > "$tmp/v-fail.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: not yet
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-fail.yaml" >/dev/null

# Approve everything humanly possible.
"$REPO_GS" approve goal >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" approve memory-patch >/dev/null 2>&1 || true
"$REPO_GS" approve high-risk action-1 >/dev/null
"$REPO_GS" approve regression-waiver REG-X >/dev/null

# complete must still fail: human approval cannot convert fail verdict to pass.
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
  bad "complete succeeded despite fail verdict (approval cannot convert fail->pass)"
else
  ok "complete still blocked by fail verdict despite all approvals"
fi

# Approve kinds not in the allowed list must be rejected.
for bad_kind in criteria verdict result pass; do
  if "$REPO_GS" approve "$bad_kind" >/dev/null 2>&1; then
    bad "approve accepted forbidden kind: $bad_kind"
  fi
done
ok "approve rejects unauthorized kinds"

[ "$TESTS_FAIL" -eq 0 ]
