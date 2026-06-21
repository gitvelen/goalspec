#!/usr/bin/env bash
# GOALC #38: all-pass run generates close package and enters ready_to_close.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-38
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p38"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" run >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
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
patches: []
YML


# A premature close from running should explain that /goalspec run must generate
# the close package first, not just report a generic state mismatch.
premature="$($REPO_GS close 2>&1 >/dev/null || true)"
echo "$premature" | grep -Eq 'close package is not (ready|generated yet)'   && echo "$premature" | grep -q '/goalspec run'   && ok "close in running state points to /goalspec run close-readiness"   || bad "close in running state did not explain close-readiness path: $premature"

out="$($REPO_GS run)"
echo "$out" | grep -q 'CLOSE_PACKAGE_READY: true' && ok "run reports close package ready" || bad "run did not report close package ready"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "ready_to_close" ] && ok "state enters ready_to_close" || bad "state is not ready_to_close"
[ -f "$REPO/.goalspec/active/close-package.yaml" ] && ok "close package yaml exists" || bad "close package yaml missing"
[ "$(yq e '.hashes.close_package_hash // ""' "$REPO/.goalspec/active/close-package.yaml")" != "null" ] && ok "close package hash recorded" || bad "close package hash missing"
[ "$(yq e '.delivery.mode // ""' "$REPO/.goalspec/active/close-package.yaml")" = "github_pr" ] && ok "close package records delivery mode" || bad "close package missing delivery mode"
status_out="$($REPO_GS status)"
echo "$status_out" | grep -q '^CLOSE_READY: true' && ok "status reports close ready" || bad "status does not report close ready"

[ "$TESTS_FAIL" -eq 0 ]
