#!/usr/bin/env bash
# Test: goalspec evidence template prints a WU-scoped entry carrying the current
#       contract_hash and the WU's criteria/evidence-requirement refs; and
#       evidence check passes when an entry's contract_hash is current and fails
#       (stale) when it does not match the frozen contract.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-30
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p30"; mkdir -p "$tmp"
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
ef="$REPO/.goalspec/active/evidence.yaml"

# 1. template prints a WU-001 entry with current contract_hash + refs.
tpl="$("$REPO_GS" evidence template WU-001)"
printf '%s\n' "$tpl" | grep -q 'work_unit_ref: "WU-001"' && ok "template has work_unit_ref WU-001" || bad "template missing work_unit_ref"
printf '%s\n' "$tpl" | grep -q 'criteria_refs: \["CRIT-001"\]' && ok "template has criteria_refs [CRIT-001]" || bad "template missing criteria_refs"
printf '%s\n' "$tpl" | grep -q 'evidence_requirement_refs: \["EVIDREQ-001"\]' && ok "template has evidence_requirement_refs [EVIDREQ-001]" || bad "template missing evidence_requirement_refs"
printf '%s\n' "$tpl" | grep -q "contract_hash: \"$CHASH\"" && ok "template carries current contract_hash" || bad "template missing/wrong contract_hash"

# 2. evidence check passes when entry contract_hash is current.
cat > "$ef" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
    exit_code: 0
    artifact_paths: []
YML
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  ok "evidence check passes with current contract_hash"
else
  bad "evidence check failed with current contract_hash"
fi

# 3. evidence check fails when entry contract_hash is stale.
cat > "$ef" <<YML
evidence:
  - id: EV-001
    contract_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
    exit_code: 0
    artifact_paths: []
YML
if "$REPO_GS" evidence check >/dev/null 2>&1; then
  bad "evidence check passed with stale contract_hash (should fail)"
else
  ok "evidence check fails with stale contract_hash"
fi

[ "$TESTS_FAIL" -eq 0 ]
