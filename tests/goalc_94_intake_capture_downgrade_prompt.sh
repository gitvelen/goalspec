#!/usr/bin/env bash
# GOALC #94: intake-capture review #4 (downgrade) covers the capture's
#            projection into constraint-suggestions.yaml — not just capture.md
#            wording — and requires source_refs to trace to a concrete capture
#            id. Regression for the velentrade GOAL-20260715-001 capture->
#            constraint downgrade gap (a strong user acceptance signal silently
#            dropped or weakened hard->soft in the constraints slipped past the
#            review because #4 only compared capture.md vs conversation).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac }

fresh_initialized_repo goalc-94
"$REPO_GS" start "intent" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
x
MD

prompt="$("$REPO_GS" review prompt intake-capture 2>&1)"

# #4 must now name constraint-suggestions.yaml as a compared artifact, so the
# reviewer compares the constraint projection against the conversation too.
contains "$prompt" "constraint-suggestions.yaml" \
  && ok "intake-capture review #4 covers constraint-suggestions.yaml" \
  || bad "intake-capture review #4 does not mention constraint-suggestions.yaml"

# #4 must require source_refs to cite a concrete id (not a vague [conversation]).
contains "$prompt" "source_refs" \
  && ok "intake-capture review #4 requires source_refs traceability" \
  || bad "intake-capture review #4 missing source_refs requirement"

[ "$TESTS_FAIL" -eq 0 ]
