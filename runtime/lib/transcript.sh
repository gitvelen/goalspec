#!/usr/bin/env bash
# transcript.sh — rebuild intake-conversation.md from AI tool session transcripts.
#
# The intake `end` command calls goalspec_transcript_rebuild to mechanically
# slice the [started_at, ended_at] window out of the current AI tool's on-disk
# session transcript and rewrite active/intake-conversation.md. No AI authoring:
# content comes straight from the transcript, so the record is lossless and
# independent of AI attention/memory (the original failure mode where the AI
# forgot to append turns, or appended lossy paraphrases).
#
# Providers abstract per-tool storage. Claude Code keeps an append-only jsonl
# transcript that compact never touches (lossless even after compaction). Codex
# keeps rollout jsonl under ~/.codex/sessions. Provider roots honor env overrides
# (GOALSPEC_TRANSCRIPT_CLAUDE_ROOT / _CODEX_ROOT) so tests can stub them.

# Whether jq is available. Slicing depends on it; without jq, rebuild degrades.
goalspec_transcript_has_jq() {
  command -v jq >/dev/null 2>&1
}

# Detect the active provider by session-root existence. Echoes claude|codex or
# nothing. Provider roots respect the env overrides above.
goalspec_transcript_claude_root() {
  printf '%s\n' "${GOALSPEC_TRANSCRIPT_CLAUDE_ROOT:-$HOME/.claude}"
}

goalspec_transcript_codex_root() {
  printf '%s\n' "${GOALSPEC_TRANSCRIPT_CODEX_ROOT:-$HOME/.codex}"
}

goalspec_transcript_detect() {
  if [ -d "$(goalspec_transcript_claude_root)/projects" ]; then
    echo claude
  elif [ -d "$(goalspec_transcript_codex_root)/sessions" ]; then
    echo codex
  fi
}

# --- claude provider: <root>/projects/<cwd-id>/<session>.jsonl --------------

# cwd absolute path → claude project id: '/' and '.' both become '-'.
goalspec_transcript_claude_project_id() {
  local cwd="${1:-$PWD}"
  printf '%s' "$cwd" | tr '/.' '--'
}

# Echo the newest .jsonl under the project's transcript dir, or return 1.
goalspec_transcript_claude_locate() {
  local cwd="${1:-$PWD}" dir latest
  dir="$(goalspec_transcript_claude_root)/projects/$(goalspec_transcript_claude_project_id "$cwd")"
  [ -d "$dir" ] || return 1
  latest="$(find "$dir" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)"
  [ -n "$latest" ] || return 1
  printf '%s\n' "$latest"
}

# Render windowed turns as markdown. Timestamps are ISO-8601 'Z'; transcript
# rows carry milliseconds (e.g. ...50.515Z) while goalspec_now is second-level
# (...50Z). Strip the fractional part before comparing or a same-second row
# sorts '.' < 'Z' and is wrongly excluded.
goalspec_transcript_claude_render() {
  local file="$1" start="$2" end="$3"
  jq -r --arg s "$start" --arg e "$end" '
    select(.type == "user" or .type == "assistant")
    | (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $ts
    | select($ts != "" and $ts >= $s and $ts <= $e)
    | (.message.content | if type == "array" then . else [{type:"text", text:.}] end) as $blocks
    | "## " + .type + "  (" + (.timestamp // "") + ")\n"
      + ($blocks | map(
          if .type == "text" then (.text // "")
          elif .type == "thinking" then "\n**[thinking]**\n" + (.thinking // "") + "\n"
          elif .type == "tool_use" then "\n**tool_use: " + (.name // "?") + "**\n```json\n" + (.input | tostring) + "\n```\n"
          elif .type == "tool_result" then "\n**tool_result** (" + (.tool_use_id // "") + "):\n" + ((.content | if type == "string" then . else tostring end)) + "\n"
          else "" end
        ) | join("\n"))
  ' "$file" 2>/dev/null
}

# --- codex provider: <root>/sessions/YYYY/MM/DD/rollout-*.jsonl -------------

# Echo the rollout whose session_meta.cwd matches the project, falling back to
# the newest by mtime. Returns 1 if no rollout exists.
goalspec_transcript_codex_locate() {
  local cwd="${1:-$PWD}" base candidates f match=""
  base="$(goalspec_transcript_codex_root)/sessions"
  [ -d "$base" ] || return 1
  candidates="$(find "$base" -name 'rollout-*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
                | sort -rn | head -20 | cut -d' ' -f2-)"
  [ -n "$candidates" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(jq -r --arg c "$cwd" 'select(.type=="session_meta") | .payload.cwd // ""' "$f" 2>/dev/null | head -1)" = "$cwd" ]; then
      match="$f"; break
    fi
  done <<<"$candidates"
  [ -n "$match" ] && printf '%s\n' "$match" || printf '%s\n' "$candidates" | head -1
}

# Codex message turns only (input_text/output_text). Reasoning, function_call
# and function_call_output are separate response_items without a role; capturing
# them is left to a later provider enhancement (noted in the ADR).
goalspec_transcript_codex_render() {
  local file="$1" start="$2" end="$3"
  jq -r --arg s "$start" --arg e "$end" '
    select(.type == "response_item" and .payload.type == "message")
    | (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $ts
    | select($ts != "" and $ts >= $s and $ts <= $e)
    | (.payload.content | if type == "array" then . else [{type:"text", text:.}] end) as $blocks
    | "## " + (.payload.role // "?") + "  (" + (.timestamp // "") + ")\n"
      + ($blocks | map(
          if .type == "input_text" or .type == "output_text" then (.text // "")
          elif .type == "input_image" then "[image]"
          else "" end
        ) | join("\n"))
  ' "$file" 2>/dev/null
}

# --- orchestrator -----------------------------------------------------------

# Rebuild active/intake-conversation.md from the transcript window. Returns 0
# and atomically rewrites the file on success; returns 1 and leaves the file
# untouched on any failure (no provider, no file, no jq, empty window) so the
# caller can fall back to the begin skeleton instead of silently emptying it.
goalspec_transcript_rebuild() {
  local started_at="$1" ended_at="$2" cwd="${3:-$PWD}" conv provider file turns tmp
  [ -n "$started_at" ] && [ -n "$ended_at" ] || return 1
  goalspec_transcript_has_jq || { echo "goalspec transcript: jq not found; cannot slice" >&2; return 1; }
  conv="$(goalspec_intake_conversation_file)"
  provider="$(goalspec_transcript_detect)"
  [ -n "$provider" ] || { echo "goalspec transcript: no AI session root found" >&2; return 1; }
  file="$(goalspec_transcript_${provider}_locate "$cwd" "$started_at")"
  [ -n "$file" ] || { echo "goalspec transcript: no session file for provider '$provider' (cwd=$cwd)" >&2; return 1; }
  turns="$(goalspec_transcript_${provider}_render "$file" "$started_at" "$ended_at")"
  if [ -z "$turns" ]; then
    echo "goalspec transcript: no turns in window [$started_at .. $ended_at] from $file" >&2
    return 1
  fi
  tmp="${conv}.tmp"
  {
    printf '# Intake Conversation\n\n'
    printf 'source: %s (%s)\n' "$provider" "$file"
    printf 'window: %s .. %s\n\n' "$started_at" "$ended_at"
    printf '%s\n' "$turns"
    printf '\n## Capture Instruction\n'
    printf 'Generate active/intake-capture.md and active/constraint-suggestions.yaml from this conversation and any intake sources, then ask the human to confirm the intake package before writing final goal.md or project constraints.\n'
  } > "$tmp" && mv "$tmp" "$conv"
}

# Resolve the located transcript path for the detected provider (used to record
# provenance in intake-sources.yaml). Echoes the path or nothing.
goalspec_transcript_current_path() {
  local cwd="${1:-$PWD}" started_at="${2:-}" provider
  provider="$(goalspec_transcript_detect)" || return 1
  [ -n "$provider" ] || return 1
  goalspec_transcript_${provider}_locate "$cwd" "$started_at"
}
