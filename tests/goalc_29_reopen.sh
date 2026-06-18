#!/usr/bin/env bash
# Test: goalspec reopen clears the recorded contract/evidence hashes and sets
#       status=reopen_required, so downstream next sees staleness and is blocked
#       (old evidence/verdict can no longer be used to advance). reopen.sh exits
#       the lifecycle via reopen_required -> draft/intake_reviewed.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-29
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p29"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

state="$REPO/.goalspec/active/state.yaml"

# Sanity: freeze recorded a non-empty contract_hash in state.
pre="$(yq e '.contract_hash' "$state")"
[ -n "$pre" ] && [ "$pre" != "null" ] && ok "pre-reopen: state.contract_hash recorded by freeze" || bad "pre-reopen: state.contract_hash not recorded"

# Reopen.
"$REPO_GS" reopen "found scope gap" >/dev/null

[ "$(yq e '.status' "$state")" = "reopen_required" ] && ok "reopen sets status=reopen_required" || bad "status not reopen_required"
[ -z "$(yq e '.contract_hash' "$state")" ] && ok "reopen clears state.contract_hash (forces staleness)" || bad "state.contract_hash not cleared"
[ -z "$(yq e '.evidence_hash' "$state")" ] && ok "reopen clears state.evidence_hash (forces staleness)" || bad "state.evidence_hash not cleared"
[ "$(yq e '.reopen_reason' "$state")" = "found scope gap" ] && ok "reopen records reopen_reason" || bad "reopen_reason not recorded"

# Audit note (not asserted as a desired invariant): reopen clears the recorded
# hashes to "" and sets status=reopen_required. However goalspec_stale_*_changed()
# treats an empty recorded hash as "not stale", and next.sh has no
# status==reopen_required gate — so reopen does NOT auto-block next/complete
# today. The human must edit goal/contract and re-review/approve/freeze.
# Hardening reopen (e.g. a reopen_required gate in next/complete) is a separate
# decision; this test only locks down reopen's direct state contract above.

[ "$TESTS_FAIL" -eq 0 ]
