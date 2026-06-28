#!/usr/bin/env bash
# GOALC #62: intake-conversation.md is rebuilt mechanically from the AI tool's
# on-disk session transcript at `intake end` — lossless, independent of AI
# authoring. Covers the claude provider (incl. AskUserQuestion preservation),
# the codex provider, and graceful fallback when no transcript is locatable.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CODEX_EMPTY="$TESTS_TMP_ROOT/codex-empty"
mkdir -p "$CODEX_EMPTY"

# --- case 1: claude provider rebuilds a sliced, lossless conversation -------
fresh_initialized_repo goalc-62-claude-slice
export GOALSPEC_TRANSCRIPT_CLAUDE_ROOT="$TESTS_TMP_ROOT/claude-home-1"
export GOALSPEC_TRANSCRIPT_CODEX_ROOT="$CODEX_EMPTY"

pid="$(printf '%s' "$REPO" | tr '/.' '--')"
mockf="$GOALSPEC_TRANSCRIPT_CLAUDE_ROOT/projects/$pid/sess.jsonl"
mkdir -p "$(dirname "$mockf")"
# The AI session predates the goalspec window: seed a placeholder turn so
# begin-time provenance can resolve the transcript path before the real
# in-window turns are appended.
echo '{"type":"user","timestamp":"2000-01-01T00:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"seed"}]}}' > "$mockf"

"$REPO_GS" intake begin "slice my conversation" >/dev/null

# begin must no longer write a stale status: collecting line (state.yaml is truth).
grep -q '^status: collecting' "$REPO/.goalspec/active/intake-conversation.md" \
  && bad "begin wrote stale status: collecting into conversation.md" \
  || ok "begin no longer writes status: collecting"

started_at="$(yq e '.intake_session.started_at' "$REPO/.goalspec/active/state.yaml")"
cat > "$mockf" <<JSONL
{"type":"user","timestamp":"$started_at","message":{"role":"user","content":[{"type":"text","text":"should we gate this behind a feature flag?"}]}}
{"type":"assistant","timestamp":"$started_at","message":{"role":"assistant","content":[{"type":"text","text":"yes"},{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"which default?","options":[{"label":"on"},{"label":"off"}]}]}}]}}
JSONL

"$REPO_GS" intake end 2>"$TESTS_TMP_ROOT/enderr1" >/dev/null
conv="$REPO/.goalspec/active/intake-conversation.md"

[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "end closes collection after rebuild" \
  || bad "end did not close collection"
grep -q 'feature flag' "$conv" && ok "sliced user turn present" || bad "sliced user turn missing"
grep -q 'AskUserQuestion' "$conv" && ok "sliced tool_use present" || bad "sliced tool_use missing"
grep -q 'which default' "$conv" && ok "AskUserQuestion options preserved" || bad "AskUserQuestion options lost"
grep -q '^source: claude' "$conv" && ok "source provenance recorded" || bad "source provenance missing"
grep -q '## Capture Instruction' "$conv" && ok "capture instruction present" || bad "capture instruction missing"
grep -q '^status: collecting' "$conv" && bad "stale status leaked into rebuilt file" || ok "no stale status in rebuilt file"
[ -s "$TESTS_TMP_ROOT/enderr1" ] && bad "end emitted unexpected stderr" || ok "end silent on success"

src_path="$(yq e '.sources[] | select(.type=="conversation") | .path' "$REPO/.goalspec/active/intake-sources.yaml")"
case "$src_path" in
  */sess.jsonl) ok "conversation source points at transcript path" ;;
  *) bad "conversation source not traceable: $src_path" ;;
esac
bound_path="$(yq e '.intake_session.transcript.path // ""' "$REPO/.goalspec/active/state.yaml")"
[ "$bound_path" = "$src_path" ] && ok "conversation source uses begin-bound transcript" || bad "bound transcript mismatch: bound=$bound_path source=$src_path"

# A newer same-project transcript appearing after begin must not steal the slice.
fresh_initialized_repo goalc-62-claude-bound
export GOALSPEC_TRANSCRIPT_CLAUDE_ROOT="$TESTS_TMP_ROOT/claude-home-bound"
export GOALSPEC_TRANSCRIPT_CODEX_ROOT="$CODEX_EMPTY"
pid="$(printf '%s' "$REPO" | tr '/.' '--')"
oldf="$GOALSPEC_TRANSCRIPT_CLAUDE_ROOT/projects/$pid/old.jsonl"
newf="$GOALSPEC_TRANSCRIPT_CLAUDE_ROOT/projects/$pid/new.jsonl"
mkdir -p "$(dirname "$oldf")"
echo '{"type":"user","timestamp":"2000-01-01T00:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"seed old"}]}}' > "$oldf"
"$REPO_GS" intake begin "bind old transcript" >/dev/null
started_at="$(yq e '.intake_session.started_at' "$REPO/.goalspec/active/state.yaml")"
cat > "$oldf" <<JSONL
{"type":"user","timestamp":"$started_at","message":{"role":"user","content":[{"type":"text","text":"old transcript content"}]}}
JSONL
cat > "$newf" <<JSONL
{"type":"user","timestamp":"$started_at","message":{"role":"user","content":[{"type":"text","text":"new transcript should not appear"}]}}
JSONL
touch "$newf"
"$REPO_GS" intake end >/dev/null 2>"$TESTS_TMP_ROOT/enderr-bound"
conv="$REPO/.goalspec/active/intake-conversation.md"
grep -q 'old transcript content' "$conv" && ok "begin-bound transcript content used" || bad "begin-bound transcript content missing"
grep -q 'new transcript should not appear' "$conv" && bad "newer transcript stole intake slice" || ok "newer transcript did not steal intake slice"
bound_src="$(yq e '.sources[] | select(.type=="conversation") | .path' "$REPO/.goalspec/active/intake-sources.yaml")"
case "$bound_src" in
  */old.jsonl) ok "conversation source stayed bound to old transcript" ;;
  *) bad "conversation source not bound to old transcript: $bound_src" ;;
esac

# --- case 2: codex provider rebuilds message turns --------------------------
fresh_initialized_repo goalc-62-codex-slice
# claude root absent so detect falls through to codex.
export GOALSPEC_TRANSCRIPT_CLAUDE_ROOT="$TESTS_TMP_ROOT/claude-absent"
export GOALSPEC_TRANSCRIPT_CODEX_ROOT="$TESTS_TMP_ROOT/codex-home-2"
"$REPO_GS" intake begin "codex conversation" >/dev/null
started_at="$(yq e '.intake_session.started_at' "$REPO/.goalspec/active/state.yaml")"
mkdir -p "$GOALSPEC_TRANSCRIPT_CODEX_ROOT/sessions/2026/06/24"
codf="$GOALSPEC_TRANSCRIPT_CODEX_ROOT/sessions/2026/06/24/rollout-2026-06-24T00-00-00-00000000-0000.jsonl"
cat > "$codf" <<JSONL
{"type":"session_meta","timestamp":"$started_at","payload":{"cwd":"$REPO","id":"s1"}}
{"type":"response_item","timestamp":"$started_at","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"codex asks about caching"}]}}
{"type":"response_item","timestamp":"$started_at","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"cache the outputs"}]}}
JSONL

"$REPO_GS" intake end 2>"$TESTS_TMP_ROOT/enderr2" >/dev/null
conv="$REPO/.goalspec/active/intake-conversation.md"
grep -q 'codex asks about caching' "$conv" && ok "codex user turn present" || bad "codex user turn missing"
grep -q 'cache the outputs' "$conv" && ok "codex assistant turn present" || bad "codex assistant turn missing"
grep -q '^source: codex' "$conv" && ok "codex source provenance recorded" || bad "codex source provenance missing"

# --- case 3: graceful fallback when no transcript is locatable --------------
fresh_initialized_repo goalc-62-fallback
export GOALSPEC_TRANSCRIPT_CLAUDE_ROOT="$TESTS_TMP_ROOT/claude-absent"
export GOALSPEC_TRANSCRIPT_CODEX_ROOT="$CODEX_EMPTY"
"$REPO_GS" intake begin "fallback case" >/dev/null
"$REPO_GS" intake end 2>"$TESTS_TMP_ROOT/enderr3" >/dev/null

[ "$(yq e '.intake_session.status' "$REPO/.goalspec/active/state.yaml")" = "closed" ] \
  && ok "end still closes when transcript absent" \
  || bad "end blocked by missing transcript"
grep -q 'Turn 1 - User' "$REPO/.goalspec/active/intake-conversation.md" \
  && ok "begin skeleton retained on fallback" \
  || bad "begin skeleton lost on fallback"
grep -q '## Capture Instruction' "$REPO/.goalspec/active/intake-conversation.md" \
  && ok "capture instruction appended on fallback" \
  || bad "capture instruction missing on fallback"
grep -qi 'warning' "$TESTS_TMP_ROOT/enderr3" \
  && ok "fallback emits warning" \
  || bad "fallback silent (should warn)"

[ "$TESTS_FAIL" -eq 0 ]
