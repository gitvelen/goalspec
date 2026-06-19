#!/usr/bin/env bash
# GOALC #40: close performs git delivery and records closed metadata.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-40
install_fake_gh
setup_test_remote
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true

"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p40"; mkdir -p "$tmp"
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
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
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
"$REPO_GS" run >/dev/null

if "$REPO_GS" close >/tmp/goalspec-close40.out 2>&1; then
  ok "close succeeds with fake gh and remote"
else
  cat /tmp/goalspec-close40.out >&2
  bad "close failed"
fi

[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] && ok "state is closed" || bad "state not closed"
[ -f "$REPO/.goalspec/history/v0001/delivery.yaml" ] && ok "delivery metadata written" || bad "delivery metadata missing"
[ "$(yq e '.pr_url' "$REPO/.goalspec/history/v0001/delivery.yaml")" = "https://example.test/org/repo/pull/1" ] && ok "PR URL recorded" || bad "PR URL not recorded"
[ -n "$(yq e '.close.main_commit // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "main commit recorded" || bad "main commit missing"
[ -n "$(yq e '.close.branch // ""' "$REPO/.goalspec/active/state.yaml")" ] && ok "branch recorded" || bad "branch missing"

[ "$TESTS_FAIL" -eq 0 ]
