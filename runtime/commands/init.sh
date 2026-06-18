#!/usr/bin/env bash
# init.sh — initialize .goalspec/ in current git repo by copying framework.
set -uo pipefail

# Framework source: the directory this script's .goalspec lives in.
# This script is at <framework>/.goalspec/runtime/commands/init.sh; framework
# root is runtime/../.. (the .goalspec dir).
SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_PROJECT_ROOT="$(dirname "$SRC_ROOT")"

# Resolve yq (system mikefarah v4, else vendored binary) before any yq use
# below — init must work on targets that have no yq installed. yq.sh is
# dependency-free so it loads cleanly here.
# shellcheck disable=SC1091
. "$SRC_ROOT/runtime/lib/yq.sh"
goalspec_setup_yq "$SRC_ROOT" || exit 1

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "usage: goalspec init [project-path]   (default: current directory)" >&2
  exit 0
fi

GOALSPEC_GUIDE_BEGIN='<!-- GOALSPEC:BEGIN -->'
GOALSPEC_GUIDE_END='<!-- GOALSPEC:END -->'

goalspec_legacy_ai_guide() {
  local file="$1"
  /bin/grep -q '^# Goalspec' "$file" 2>/dev/null || return 1
  /bin/grep -q '本项目使用 Goalspec 框架' "$file" 2>/dev/null || return 1
  /bin/grep -q '.goalspec/goalspec status' "$file" 2>/dev/null || return 1
}

goalspec_install_ai_guide() {
  local dest_file="$1" template_file="$2"
  local begin_count end_count tmp

  if [ ! -f "$dest_file" ]; then
    cp "$template_file" "$dest_file"
    return 0
  fi

  begin_count="$(/bin/grep -cF "$GOALSPEC_GUIDE_BEGIN" "$dest_file" 2>/dev/null || true)"
  end_count="$(/bin/grep -cF "$GOALSPEC_GUIDE_END" "$dest_file" 2>/dev/null || true)"

  if [ "$begin_count" = "1" ] && [ "$end_count" = "1" ]; then
    tmp="$(mktemp "${dest_file}.tmp.XXXXXX")" || return 1
    awk -v begin="$GOALSPEC_GUIDE_BEGIN" -v end="$GOALSPEC_GUIDE_END" -v repl="$template_file" '
      BEGIN {
        while ((getline line < repl) > 0) {
          replacement = replacement line ORS
        }
        close(repl)
        in_block = 0
      }
      $0 == begin {
        printf "%s", replacement
        in_block = 1
        next
      }
      $0 == end {
        in_block = 0
        next
      }
      !in_block { print }
    ' "$dest_file" > "$tmp" && mv "$tmp" "$dest_file"
    [ ! -f "$tmp" ] || rm -f "$tmp"
    return 0
  fi

  if [ "$begin_count" != "0" ] || [ "$end_count" != "0" ]; then
    echo "goalspec init: warning: $dest_file has a malformed managed Goalspec block; leaving unchanged." >&2
    return 0
  fi

  if goalspec_legacy_ai_guide "$dest_file"; then
    cp "$template_file" "$dest_file"
    return 0
  fi

  {
    printf '\n'
    cat "$template_file"
  } >> "$dest_file"
}

goalspec_update_existing() {
  local dest_root="$1" dest_goalspec="$2"
  local ans
  printf 'goalspec init: %s already exists. Update framework code and role templates while preserving project state? [y/N] ' "$dest_goalspec" >&2
  if ! IFS= read -r ans; then
    echo "goalspec init: update cancelled." >&2
    exit 1
  fi
  case "$ans" in
    y|Y) ;;
    *) echo "goalspec init: update cancelled." >&2; exit 1 ;;
  esac

  rm -rf "$dest_goalspec/runtime" "$dest_goalspec/ai"
  rm -rf "$dest_goalspec/skills"
  cp -R "$SRC_ROOT/runtime" "$dest_goalspec/runtime"
  cp -R "$SRC_ROOT/runtime/templates/ai" "$dest_goalspec/ai"
  cp -R "$SRC_ROOT/skills" "$dest_goalspec/skills"
  cp "$SRC_ROOT/goalspec" "$dest_goalspec/goalspec"
  chmod +x "$dest_goalspec/goalspec"

  mkdir -p "$dest_goalspec/history" "$dest_goalspec/artifacts" "$dest_goalspec/artifacts/intake" "$dest_goalspec/active" "$dest_goalspec/project"
  for f in intake-sources.yaml intake-conversation.md intake-capture.md constraint-suggestions.yaml goal.yaml criteria.yaml constraints.yaml goal-driven-prompt.md; do
    if [ ! -f "$dest_goalspec/active/$f" ]; then
      cp "$SRC_ROOT/runtime/templates/active/$f" "$dest_goalspec/active/$f"
    fi
  done
  if [ -f "$dest_goalspec/active/state.yaml" ]; then
    yq e -i '
      .intake_capture_hash = (.intake_capture_hash // null) |
      .intake_package_hash = (.intake_package_hash // null) |
      .constraint_suggestions_applied_hash = (.constraint_suggestions_applied_hash // null) |
      .intake_session = (.intake_session // {"status":"not_started","started_at":null,"ended_at":null}) |
      .intake_session.status = (.intake_session.status // "not_started") |
      .intake_session.started_at = (.intake_session.started_at // null) |
      .intake_session.ended_at = (.intake_session.ended_at // null)
    ' "$dest_goalspec/active/state.yaml"
  else
    cp "$SRC_ROOT/runtime/templates/active/state.yaml" "$dest_goalspec/active/state.yaml"
  fi

  goalspec_install_ai_guide "$dest_root/AGENTS.md" "$SRC_ROOT/runtime/templates/AGENTS.md"
  goalspec_install_ai_guide "$dest_root/CLAUDE.md" "$SRC_ROOT/runtime/templates/CLAUDE.md"

  echo "goalspec: updated $dest_goalspec"
  echo "  project state preserved: active/, project/, history/, artifacts/"
  echo "next step: .goalspec/goalspec status"
}

# Optional target project path (default: current directory). Lets
# `goalspec install <path>` / `goalspec init <path>` target an explicit project
# without having to cd into it first.
dest_root="${1:-$PWD}"
dest_goalspec="$dest_root/.goalspec"

# Must be a git repo.
if ! git -C "$dest_root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "goalspec init: current directory is not a git repo. Please run 'git init' first." >&2
  exit 1
fi

# Existing .goalspec/ becomes an explicit update flow.
if [ -e "$dest_goalspec" ]; then
  goalspec_update_existing "$dest_root" "$dest_goalspec"
  exit 0
fi

mkdir -p "$dest_goalspec"

# Copy framework skeleton.
# runtime/ holds code; templates live under runtime/templates/{active,project,ai}.
cp -R "$SRC_ROOT/runtime" "$dest_goalspec/runtime"
cp -R "$SRC_ROOT/skills" "$dest_goalspec/skills"
mkdir -p "$dest_goalspec/history" "$dest_goalspec/artifacts"
# active/ and project/ start from templates.
cp -R "$SRC_ROOT/runtime/templates/active" "$dest_goalspec/active"
cp -R "$SRC_ROOT/runtime/templates/project" "$dest_goalspec/project"
cp -R "$SRC_ROOT/runtime/templates/ai" "$dest_goalspec/ai"

# Copy top-level dispatch.
cp "$SRC_ROOT/goalspec" "$dest_goalspec/goalspec"
chmod +x "$dest_goalspec/goalspec"

# Copy VERSION if present.
[ -f "$SRC_ROOT/runtime/VERSION" ] && cp "$SRC_ROOT/runtime/VERSION" "$dest_goalspec/runtime/VERSION"

# Ensure runtime/commands exist (they were copied with runtime/).
# Install or update the managed Goalspec guide in project root AI instruction files.
goalspec_install_ai_guide "$dest_root/AGENTS.md" "$SRC_ROOT/runtime/templates/AGENTS.md"
goalspec_install_ai_guide "$dest_root/CLAUDE.md" "$SRC_ROOT/runtime/templates/CLAUDE.md"

# Initialize empty history / artifacts.
mkdir -p "$dest_goalspec/history" "$dest_goalspec/artifacts"

echo "goalspec: initialized $dest_goalspec"
echo "  project root: $dest_root"
echo "next step: .goalspec/goalspec status"
