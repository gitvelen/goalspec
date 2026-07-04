#!/usr/bin/env bash
# GOALC #82: approve intake-package is gated on a passing, fresh intake-capture
# review. This is the hard gate that enforces the adversarial intent-coverage
# review of intake-capture.md against intake-conversation.md — the only review
# that reads the conversation (intake/contract reviews are fresh-context form
# checks and deliberately do not). Without this gate, intent drops in the
# capture launder silently into goal.md / contract.yaml.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-82-gate
"$REPO_GS" start "ship an intent-bearing change" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Ship something.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
YML

# 1. approve intake-package WITHOUT an intake-capture review -> blocked.
if "$REPO_GS" approve intake-package >/dev/null 2>"$TESTS_TMP_ROOT/g82-noreview.err"; then
  bad "approve intake-package accepted without intake-capture review"
else
  /bin/grep -q 'intake-capture review has not passed' "$TESTS_TMP_ROOT/g82-noreview.err" \
    && ok "approve intake-package blocked without intake-capture review" \
    || bad "block message wrong: $(head -1 "$TESTS_TMP_ROOT/g82-noreview.err")"
fi

# 2. the prompt exists and instructs a hot-context (conversation-reading) review.
"$REPO_GS" review prompt intake-capture 2>&1 | /bin/grep -q 'intake-conversation.md' \
  && ok "intake-capture review prompt reads the conversation" \
  || bad "intake-capture review prompt does not read the conversation"

# 3. stamp a passing review -> approve succeeds.
stamp_intake_capture_review_pass
"$REPO_GS" approve intake-package >/dev/null \
  && ok "approve intake-package accepted after passing intake-capture review" \
  || bad "approve intake-package rejected despite passing intake-capture review"

# 4. capture changes after the review -> review goes stale -> re-approve blocked.
echo "## Confirmed Decisions" >> "$REPO/.goalspec/active/intake-capture.md"
if "$REPO_GS" approve intake-package >/dev/null 2>"$TESTS_TMP_ROOT/g82-stale.err"; then
  bad "approve intake-package accepted with stale intake-capture review"
else
  /bin/grep -q 'stale' "$TESTS_TMP_ROOT/g82-stale.err" \
    && ok "approve intake-package blocked when capture changed after review" \
    || bad "stale block message wrong: $(head -1 "$TESTS_TMP_ROOT/g82-stale.err")"
fi

# 5. re-stamp after the edit -> approve succeeds again (recovers).
stamp_intake_capture_review_pass
"$REPO_GS" approve intake-package >/dev/null \
  && ok "approve intake-package recovers after re-stamping the review" \
  || bad "approve intake-package did not recover after re-stamp"

[ "$TESTS_FAIL" -eq 0 ]
