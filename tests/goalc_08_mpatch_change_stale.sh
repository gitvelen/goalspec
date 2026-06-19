#!/usr/bin/env bash
# GOALC #8: memory-patch.yaml change after the close package is generated makes
#            the close package stale; close must refuse to apply a tampered patch.
#            (V2: memory-patch approval is no longer a separate gate — the close
#            package hash binds the memory_patch_hash, so a change invalidates it.)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-08
install_fake_gh
setup_test_remote
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p8"; mkdir -p "$tmp"
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

# Generate the close package (run with all criteria passing).
"$REPO_GS" run >/dev/null && ok "close package generated"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "ready_to_close" ] || bad "not ready_to_close"

# Now tamper with the memory patch after the package was bound.
yq e -i '.patches[0].content.statement = "TAMPERED"' "$REPO/.goalspec/active/memory-patch.yaml"
if "$REPO_GS" close >/tmp/goalspec-mpatch.out 2>&1; then
  bad "close applied a tampered (stale) memory-patch"
else
  grep -q 'memory_patch_hash' /tmp/goalspec-mpatch.out && ok "close blocked by stale memory-patch hash" \
    || bad "close failed for unexpected reason: $(cat /tmp/goalspec-mpatch.out)"
fi

[ "$TESTS_FAIL" -eq 0 ]
