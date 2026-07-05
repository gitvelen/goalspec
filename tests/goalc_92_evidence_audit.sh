#!/usr/bin/env bash
# GOALC #92: 'goalspec evidence audit' — opt-in role-separation check.
#            produced_by=subagent must carry a non-empty subagent_transcript_path;
#            otherwise the entry must honestly say produced_by: master. This
#            fixes the velentrade v0006 incident where the Master wrote A1/A2
#            directly (subagent had been killed) yet evidence still claimed
#            produced_by: subagent. The default 'evidence check' is unchanged
#            (backward compatible with old goals and existing fixtures).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-92
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p92"; mkdir -p "$tmp"
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

# Evidence mix:
#   EV-001 produced_by=subagent WITH transcript   -> audit pass
#   EV-002 produced_by=subagent WITHOUT transcript -> audit fail (the v0006 lie)
#   EV-003 produced_by=master (no transcript needed) -> audit pass
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
    subagent_transcript_path: .claude/tasks/sub-a1.jsonl
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
  - id: EV-002
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
  - id: EV-003
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
    produced_by: master
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML

# 1. Default 'check' is backward compatible: EV-002's missing transcript is NOT
#    flagged here (the whole point of opt-in — old goals and existing fixtures
#    keep working).
chk_out="$("$REPO_GS" evidence check 2>&1)" && chk_rc=0 || chk_rc=$?
[ "$chk_rc" -eq 0 ] && ok "default 'evidence check' unaffected (backward compatible)" \
  || { echo "$chk_out" >&2; bad "default check should pass without audit rules"; }
echo "$chk_out" | grep -q 'produced_by=subagent requires' \
  && bad "default check must NOT enforce produced_by (regression)" \
  || ok "default check does not enforce produced_by rule"

# 2. Opt-in 'audit' flags EV-002.
aud_out="$("$REPO_GS" evidence audit 2>&1)" && aud_rc=0 || aud_rc=$?
[ "$aud_rc" -ne 0 ] && ok "'evidence audit' fails when subagent evidence lacks transcript" \
  || { echo "$aud_out" >&2; bad "'evidence audit' should fail on EV-002"; }
echo "$aud_out" | grep -q 'EV-002: produced_by=subagent requires subagent_transcript_path' \
  && ok "audit names EV-002 and the missing field" \
  || bad "audit message did not flag EV-002: $aud_out"
# EV-001 (with transcript) and EV-003 (master) must NOT be flagged.
echo "$aud_out" | grep -q 'EV-001: produced_by=subagent requires' \
  && bad "audit flagged EV-001 which HAS a transcript" || true
echo "$aud_out" | grep -q 'EV-003: produced_by=subagent requires' \
  && bad "audit flagged EV-003 which is master (no transcript needed)" || true

# 3. Fix EV-002 -> audit passes.
yq e -i '(.evidence[] | select(.id == "EV-002") | .subagent_transcript_path) = ".claude/tasks/sub-x.jsonl"' "$REPO/.goalspec/active/evidence.yaml"
aud_out2="$("$REPO_GS" evidence audit 2>&1)" && aud_rc2=0 || aud_rc2=$?
[ "$aud_rc2" -eq 0 ] && ok "'evidence audit' passes once every subagent entry has a transcript" \
  || { echo "$aud_out2" >&2; bad "audit should pass after fix"; }

[ "$TESTS_FAIL" -eq 0 ]
