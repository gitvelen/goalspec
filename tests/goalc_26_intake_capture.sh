#!/usr/bin/env bash
# GOALC #26: conversation intake must be explicitly captured and approved
# before compile; file sources must be snapshotted for intake provenance.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-26-conversation
"$REPO_GS" intake begin "start a captured conversation goal" >/dev/null

[ -f "$REPO/.goalspec/active/intake-conversation.md" ] \
  && ok "intake begin creates conversation log" \
  || bad "intake begin did not create conversation log"

[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "collecting" ] \
  && ok "intake begin marks collecting state" \
  || bad "intake begin did not mark collecting state"

yq e '[.sources[] | select(.type == "conversation")] | length' "$REPO/.goalspec/active/intake-sources.yaml" | grep -q '^1$' \
  && ok "conversation source recorded" \
  || bad "conversation source was not recorded"

"$REPO_GS" status | /bin/grep -q 'intake-conversation.md' \
  && ok "collecting status points to conversation log" \
  || bad "collecting status did not point to conversation log"

cat >> "$REPO/.goalspec/active/intake-conversation.md" <<'MD'

## Turn 2 - User
The feature should cache generated TTS outputs and avoid repeating identical generation work.
MD

"$REPO_GS" intake end >/dev/null
[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "intake end closes collection" \
  || bad "intake end did not close collection"

make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile accepted conversation intake without approved capture"
else
  ok "compile blocks unapproved conversation capture"
fi

cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Cache generated TTS outputs so repeated identical requests avoid duplicate generation work.

## Confirmed Decisions
- Conversation input is the source for this goal.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null
"$REPO_GS" compile >/dev/null \
  && ok "compile accepts approved conversation capture" \
  || bad "compile rejected approved conversation capture"

echo "tamper" >> "$REPO/.goalspec/active/intake-capture.md"
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "compile accepted stale intake package approval"
else
  ok "compile blocks stale intake package approval"
fi

fresh_initialized_repo goalc-26-file-source
mkdir -p "$REPO/docs"
cat > "$REPO/docs/spec.md" <<'MD'
# Spec

Build a cache for generated TTS outputs.
MD
"$REPO_GS" new-goal --source docs/spec.md "cache generated TTS outputs" >/dev/null

src_count="$(yq e '[.sources[] | select(.type == "file" and .path == "docs/spec.md")] | length' "$REPO/.goalspec/active/intake-sources.yaml")"
[ "$src_count" = "1" ] \
  && ok "file source recorded" \
  || bad "file source was not recorded"

snapshot="$(yq e '.sources[] | select(.type == "file" and .path == "docs/spec.md") | .snapshot_path' "$REPO/.goalspec/active/intake-sources.yaml")"
[ -n "$snapshot" ] && [ -f "$REPO/.goalspec/$snapshot" ] \
  && ok "file source snapshot saved" \
  || bad "file source snapshot missing"

make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
if "$REPO_GS" compile >/dev/null 2>&1; then
  bad "file source path compiled without approved intake package"
else
  ok "file source path requires approved intake package"
fi

fresh_initialized_repo goalc-26-directory-source
mkdir -p "$REPO/requirements/nested"
cat > "$REPO/requirements/main.md" <<'MD'
# Main Requirement
MD
cat > "$REPO/requirements/nested/detail.txt" <<'TXT'
detail
TXT
"$REPO_GS" new-goal --source requirements "directory source intake" >/dev/null

dir_type="$(yq e '.sources[] | select(.path == "requirements") | .type' "$REPO/.goalspec/active/intake-sources.yaml")"
[ "$dir_type" = "directory" ] \
  && ok "directory source recorded" \
  || bad "directory source was not recorded"

dir_snapshot="$(yq e '.sources[] | select(.path == "requirements") | .snapshot_path' "$REPO/.goalspec/active/intake-sources.yaml")"
dir_candidates="$(yq e '.sources[] | select(.path == "requirements") | .text_candidates_path' "$REPO/.goalspec/active/intake-sources.yaml")"
if [ -n "$dir_snapshot" ] && [ -f "$REPO/.goalspec/$dir_snapshot" ] \
  && /bin/grep -q '^main.md$' "$REPO/.goalspec/$dir_snapshot" \
  && /bin/grep -q '^nested/detail.txt$' "$REPO/.goalspec/$dir_snapshot"; then
  ok "directory source listing saved"
else
  bad "directory source listing missing expected files"
fi

if [ -n "$dir_candidates" ] && [ -f "$REPO/.goalspec/$dir_candidates" ] \
  && /bin/grep -q '^main.md$' "$REPO/.goalspec/$dir_candidates" \
  && /bin/grep -q '^nested/detail.txt$' "$REPO/.goalspec/$dir_candidates"; then
  ok "directory text candidates saved"
else
  bad "directory text candidates missing expected files"
fi

[ "$TESTS_FAIL" -eq 0 ]
