#!/usr/bin/env bash
# GOALC #93: sensor-backed close. With no smoke_tests configured but every pass
#            verdict citing reproducible evidence, the Tier-2 sensor (judge
#            apply re-runs the .command) IS an objective gate. The close must
#            report objective_gate=true, emit RALPH_WIGGUM_NOTE (not WARNING),
#            and the summary must carry sensor_backed=N. This fixes the
#            velentrade v0006 false positive where 70 sensor-verified verdicts
#            were reported as "0 backed by an objective gate".
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-93
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "local_commit"' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "local_commit, no smoke_tests"

# Build a ready-to-close state whose evidence IS reproducible (sensor-backed).
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p93"; mkdir -p "$tmp"
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
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
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
ehash="$(cur_evidence_hash)"
for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "minimal ready-to-close criterion"
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

out="$("$REPO_GS" close 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] && ok "sensor-backed close succeeds" || { echo "$out" >&2; bad "sensor-backed close should succeed"; }

# WARNING = "two optimists agreeing"; must NOT fire when sensor backs the verdicts.
if printf '%s\n' "$out" | grep -q 'RALPH_WIGGUM_WARNING'; then
  bad "RALPH_WIGGUM_WARNING should NOT fire when reproducible evidence is sensor-verified"
else
  ok "no RALPH_WIGGUM_WARNING when sensor-backed"
fi
# NOTE = advisory that smoke is absent even though sensor backed.
printf '%s\n' "$out" | grep -q 'RALPH_WIGGUM_NOTE' && ok "RALPH_WIGGUM_NOTE emitted (smoke-less advisory)" || bad "expected RALPH_WIGGUM_NOTE"
printf '%s\n' "$out" | grep -q 'SMOKE_WARNING' && ok "SMOKE_WARNING still emitted (no smoke configured)" || bad "expected SMOKE_WARNING"

summ="$(yq e '.verification_summary' "$REPO/.goalspec/history/v0001/delivery.yaml")"
printf '%s\n' "$summ" | grep -q 'objective_gate=true' && ok "summary records objective_gate=true (sensor counts)" || bad "summary missing objective_gate=true: $summ"
printf '%s\n' "$summ" | grep -q 'sensor_backed=1' && ok "summary records sensor_backed=1" || bad "summary missing sensor_backed=1: $summ"

[ "$TESTS_FAIL" -eq 0 ]
