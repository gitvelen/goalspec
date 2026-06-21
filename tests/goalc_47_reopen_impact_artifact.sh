#!/usr/bin/env bash
# GOALC #47: reopen creates a formal reopen-impact recovery artifact that records
#            the prior frozen basis and must be used to drive Criteria-level
#            impact analysis.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-47
"$REPO_GS" new-goal "reopen impact artifact" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p47"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

pre_contract="$(yq e '.contract_hash // ""' "$REPO/.goalspec/active/state.yaml")"
pre_goal="$(yq e '.goal_hash // ""' "$REPO/.goalspec/active/state.yaml")"
pre_criteria="$(yq e '.criteria_hash // ""' "$REPO/.goalspec/active/state.yaml")"
pre_constraints="$(yq e '.constraints_hash // ""' "$REPO/.goalspec/active/state.yaml")"

"$REPO_GS" reopen "criteria changed" >/dev/null
impact="$REPO/.goalspec/active/reopen-impact.yaml"
[ -f "$impact" ] && ok "reopen creates reopen-impact.yaml" || bad "reopen-impact.yaml missing"
[ "$(yq e '.status' "$impact")" = "required" ] && ok "reopen-impact starts required" || bad "reopen-impact status not required"
[ "$(yq e '.reopen_reason' "$impact")" = "criteria changed" ] && ok "reopen-impact records reason" || bad "reopen-impact reason missing"
[ "$(yq e '.contract_hash_before_reopen' "$impact")" = "$pre_contract" ] && ok "reopen-impact records prior contract hash" || bad "reopen-impact missing prior contract hash"
[ "$(yq e '.goal_hash_before_reopen' "$impact")" = "$pre_goal" ] && ok "reopen-impact records prior goal hash" || bad "reopen-impact missing prior goal hash"
[ "$(yq e '.criteria_hash_before_reopen' "$impact")" = "$pre_criteria" ] && ok "reopen-impact records prior criteria hash" || bad "reopen-impact missing prior criteria hash"
[ "$(yq e '.constraints_hash_before_reopen' "$impact")" = "$pre_constraints" ] && ok "reopen-impact records prior constraints hash" || bad "reopen-impact missing prior constraints hash"
[ "$(yq e '.reviewed_by_human' "$impact")" = "false" ] && ok "reopen-impact starts unreviewed" || bad "reopen-impact unexpectedly reviewed"

[ "$TESTS_FAIL" -eq 0 ]
