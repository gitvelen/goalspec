#!/usr/bin/env bash
# GOALC #75: re-freeze after a reopen must NOT be blocked by committed run-loop
#            business work. The old base..HEAD dirty gate flagged legitimately
#            committed work as dirty (the v0004 transcript's "dirty trap" that
#            forced a hand-edit of state.yaml); freeze now uses worktree-clean
#            (uncommitted-only) semantics. close/scope_check still use
#            base..HEAD for their own purposes and are unaffected.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-75
"$REPO_GS" new-goal "refreeze after committed run" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p75"; mkdir -p "$tmp" "$REPO/src"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
ok "initial freeze recorded base_revision"

# Simulate run-loop business work and COMMIT it. Worktree is clean vs HEAD;
# base..HEAD now contains the committed file (which the old gate mis-read as dirty).
echo "impl" > "$REPO/src/a.txt"
( cd "$REPO" && git add -A && git commit -q -m "run-loop work" )
ok "committed run-loop business work (worktree clean, base..HEAD advanced)"

# Reopen, mark impact human-reviewed, tighten a criterion, re-review/approve.
"$REPO_GS" reopen "tighten acceptance" >/dev/null
impact="$REPO/.goalspec/active/reopen-impact.yaml"
yq e -i '.analysis.summary = "Contract tightened; verdicts refreshed."' "$impact"
yq e -i '.analysis.criteria.modified = ["CRIT-001"]' "$impact"
yq e -i '.reviewed_by_human = true' "$impact"
yq e -i '.criteria[0].statement = "behavior B observed after reopen"' "$REPO/.goalspec/active/contract.yaml"
cat > "$tmp/c2.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c2.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null

if "$REPO_GS" freeze >/dev/null 2>"$tmp/refreeze.err"; then
  ok "re-freeze succeeded after committed run-loop work (dirty trap fixed)"
else
  if grep -q 'dirty' "$tmp/refreeze.err"; then
    bad "re-freeze blocked by dirty trap: $(head -1 "$tmp/refreeze.err")"
  else
    bad "re-freeze failed (other reason): $(head -1 "$tmp/refreeze.err")"
  fi
fi

[ "$TESTS_FAIL" -eq 0 ]
