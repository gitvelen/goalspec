#!/usr/bin/env bash
# GOALC #39: stale close package blocks close.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-39
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p39"; mkdir -p "$tmp"
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
reason: |
  Coverage audit:
  - claim: "test criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML
"$REPO_GS" run >/dev/null

echo y >> "$REPO/src/a.txt"
if "$REPO_GS" close >/tmp/goalspec-close.out 2>&1; then
  bad "close succeeded with stale delivery identity"
else
  grep -q 'close package stale: .*changed_files_hash' /tmp/goalspec-close.out && ok "close blocks changed-files identity drift" || bad "close failed for unexpected reason"
fi
printf 'x\n' > "$REPO/src/a.txt"

# Derived package metadata drift should not turn close into a second broad audit
# when live contract/scope/evidence/delivery safety still holds.
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.hashes.evidence_hash = "sha256:derived-drift" | .hashes.verdict_hash = "sha256:derived-drift" | .hashes.suggested_delivery_hash = "sha256:derived-drift" | .readiness.criteria_ready = false | .readiness.blockers = ["derived"]' "$REPO/.goalspec/active/close-package.yaml"
if "$REPO_GS" close >/tmp/goalspec-close-derived.out 2>&1; then
  ok "close tolerates advisory package metadata drift when live gates pass"
else
  bad "close blocked advisory package metadata drift: $(cat /tmp/goalspec-close-derived.out)"
fi

# Final verification can create files after the initial package hash check.
# Close must re-check changed_files_hash before staging delivery files.
fresh_initialized_repo goalc-39-verification-delta
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "archive_only"' "$pf"
yq e -i '.commands.test = ["mkdir -p src && echo generated > src/generated-by-verification.txt"]' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "configure verification side effect"
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
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
cat > "$tmp/v-delta-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "test criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-delta-$c.yaml" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML
"$REPO_GS" run >/dev/null
if "$REPO_GS" close >/tmp/goalspec-close-verification-delta.out 2>&1; then
  bad "close succeeded after final verification changed files"
else
  grep -q 'changed files changed during final verification' /tmp/goalspec-close-verification-delta.out \
    && ok "close blocks final verification file delta" \
    || bad "close failed without final verification delta explanation"
fi

[ "$TESTS_FAIL" -eq 0 ]
