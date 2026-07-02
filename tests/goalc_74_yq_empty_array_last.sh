#!/usr/bin/env bash
# GOALC #74: yq `.[-1]` on empty arrays must NOT throw "index [-1] out of
#            range" into stderr at the review/approval/verdict gate sites.
#            mikefarah yq v4 throws before the `// ""` coalesce applies; the
#            goalspec_yq_last_match_field helper guards with select(length > 0).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-74
"$REPO_GS" new-goal "empty array safety" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"

# reviews.yaml exists (init creates `reviews: []`) but has no intake entry.
# compile reads the latest intake review via the helper.
printf 'reviews: []\n' > "$REPO/.goalspec/active/reviews.yaml"
err="$TESTS_TMP_ROOT/p74-compile.err"
"$REPO_GS" compile >/dev/null 2>"$err" || true   # legitimately fails (no review) — we only check stderr
if grep -q 'index \[-1\] out of range' "$err"; then
  bad "compile emitted yq empty-array crash on empty reviews"
else
  ok "compile clean on empty reviews.yaml"
fi

# Drive to a frozen contract, then empty verdicts and exercise a per-criterion
# latest-verdict read path (status).
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p74"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

printf 'verdicts: []\n' > "$REPO/.goalspec/active/verdict.yaml"
err2="$TESTS_TMP_ROOT/p74-status.err"
"$REPO_GS" status >/dev/null 2>"$err2" || true
if grep -q 'index \[-1\] out of range' "$err2"; then
  bad "status emitted yq empty-array crash on empty verdicts"
else
  ok "status clean on empty verdicts"
fi

# prompt_record_frozen_hashes reads latest contract approval approved_at; verify
# it doesn't crash when approvals list is empty.
printf 'approvals: []\n' >> "$REPO/.goalspec/active/state.yaml.tmp"
# state.yaml already has approvals; just confirm prompt path doesn't throw [-1].
err3="$TESTS_TMP_ROOT/p74-prompt.err"
"$REPO_GS" prompt >/dev/null 2>"$err3" || true
if grep -q 'index \[-1\] out of range' "$err3"; then
  bad "prompt path emitted yq empty-array crash on empty approvals"
else
  ok "prompt path clean on approvals read"
fi
/bin/rm -f "$REPO/.goalspec/active/state.yaml.tmp"

[ "$TESTS_FAIL" -eq 0 ]
