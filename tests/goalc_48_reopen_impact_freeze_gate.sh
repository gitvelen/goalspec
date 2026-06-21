#!/usr/bin/env bash
# GOALC #48: after reopen, freeze must not rebuild the frozen basis until the
#            reopen-impact artifact has been completed and explicitly reviewed by
#            a human.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-48
"$REPO_GS" new-goal "reopen freeze gate" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p48"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
"$REPO_GS" reopen "missing scenario" >/dev/null

if "$REPO_GS" freeze >/tmp/goalspec-freeze48.out 2>&1; then
  bad "freeze succeeded without reviewed reopen-impact"
else
  grep -q 'reopen impact has not been reviewed by a human' /tmp/goalspec-freeze48.out \
    && ok "freeze blocked until reopen-impact reviewed" \
    || bad "freeze block did not mention reviewed reopen-impact"
fi

impact="$REPO/.goalspec/active/reopen-impact.yaml"
yq e -i '.analysis.summary = "Only CRIT-001 changes; reuse the rest."' "$impact"
yq e -i '.analysis.criteria.modified = ["CRIT-001"]' "$impact"
yq e -i '.analysis.criteria.unchanged = ["CRIT-FINAL-001"]' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"

# Recreate the approval chain required by freeze after editing the contract.
yq e -i '.criteria[0].statement = "Updated criterion after reopen"' "$REPO/.goalspec/active/contract.yaml"
cat > "$tmp/c2.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: updated after reopen
YML
"$REPO_GS" review apply "$tmp/c2.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null

if "$REPO_GS" freeze >/tmp/goalspec-freeze48-pass.out 2>&1; then
  ok "freeze succeeds after reviewed reopen-impact and refreshed approvals"
else
  cat /tmp/goalspec-freeze48-pass.out >&2
  bad "freeze still blocked after reviewed reopen-impact"
fi

[ "$(yq e '.status' "$impact")" = "reviewed" ] && ok "freeze marks reopen-impact reviewed" || bad "reopen-impact status not updated by freeze"
[ "$(yq e '.reopen_impact_hash // ""' "$REPO/.goalspec/active/state.yaml")" != "null" ] && ok "freeze records reopen impact hash in state" || bad "state missing reopen_impact_hash"

[ "$TESTS_FAIL" -eq 0 ]
