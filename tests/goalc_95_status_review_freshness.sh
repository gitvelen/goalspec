#!/usr/bin/env bash
# GOALC #95: status surfaces review freshness (missing/fresh/stale) in
#            pre-freeze drafting states, so the agent need not hand-compare
#            sha256 against reviews.yaml. Not reported once frozen (staleness
#            then already enters BLOCKERS). approve/freeze still enforce
#            freshness as a hard gate; this is pre-gate visibility only.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac }

# 1. spec_drafting: REVIEW_FRESHNESS present (reviews missing is the norm).
fresh_initialized_repo goalc-95-draft
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
out="$("$REPO_GS" status)"
contains "$out" "REVIEW_FRESHNESS:" \
  && ok "status reports REVIEW_FRESHNESS in spec_drafting" \
  || bad "status missing REVIEW_FRESHNESS in spec_drafting"

# 2. ready_to_run (frozen): REVIEW_FRESHNESS is (n/a).
fresh_initialized_repo goalc-95-frozen
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze
out2="$("$REPO_GS" status)"
contains "$out2" "REVIEW_FRESHNESS: (n/a)" \
  && ok "status REVIEW_FRESHNESS is n/a once frozen" \
  || bad "status REVIEW_FRESHNESS not n/a once frozen: $(grep REVIEW_FRESHNESS <<<"$out2")"

# 3. fresh vs stale: a passing intake review shows intake=fresh; editing goal.md
#    afterwards shows intake=stale.
fresh_initialized_repo goalc-95-stale
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
out3="$("$REPO_GS" status)"
contains "$out3" "intake=fresh" \
  && ok "status shows intake=fresh after passing review" \
  || bad "status did not show intake=fresh: $(grep REVIEW_FRESHNESS <<<"$out3")"
echo "## extra note after review" >> "$REPO/.goalspec/active/goal.md"
out4="$("$REPO_GS" status)"
contains "$out4" "intake=stale" \
  && ok "status shows intake=stale after goal.md edit" \
  || bad "status did not show intake=stale: $(grep REVIEW_FRESHNESS <<<"$out4")"

[ "$TESTS_FAIL" -eq 0 ]
