#!/usr/bin/env bash
# init.sh — initialize .goalspec/ in current git repo by copying framework.
set -uo pipefail

# Framework source: the directory this script's .goalspec lives in.
# This script is at <framework>/.goalspec/runtime/commands/init.sh; framework
# root is runtime/../.. (the .goalspec dir).
SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_PROJECT_ROOT="$(dirname "$SRC_ROOT")"

dest_root="$PWD"
dest_goalspec="$dest_root/.goalspec"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "usage: goalspec init" >&2
  exit 0
fi

# Must be a git repo.
if ! git -C "$dest_root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "goalspec init: current directory is not a git repo. Please run 'git init' first." >&2
  exit 1
fi

# Refuse to clobber an existing .goalspec/.
if [ -e "$dest_goalspec" ]; then
  echo "goalspec init: $dest_goalspec already exists. Aborting." >&2
  exit 1
fi

mkdir -p "$dest_goalspec"

# Copy framework skeleton.
for sub in runtime ai project active history artifacts; do
  if [ -d "$SRC_ROOT/$sub" ]; then
    cp -R "$SRC_ROOT/$sub" "$dest_goalspec/$sub"
  else
    mkdir -p "$dest_goalspec/$sub"
  fi
done

# Copy top-level dispatch.
cp "$SRC_ROOT/goalspec" "$dest_goalspec/goalspec"
chmod +x "$dest_goalspec/goalspec"

# Copy VERSION if present.
[ -f "$SRC_ROOT/runtime/VERSION" ] && cp "$SRC_ROOT/runtime/VERSION" "$dest_goalspec/runtime/VERSION"

# Ensure runtime/commands exist (they were copied with runtime/).
# Ensure AGENTS.md / CLAUDE.md templates exist at project root (only if absent).
if [ ! -f "$dest_root/AGENTS.md" ]; then
  cp "$SRC_ROOT/runtime/templates/AGENTS.md" "$dest_root/AGENTS.md"
fi
if [ ! -f "$dest_root/CLAUDE.md" ]; then
  cp "$SRC_ROOT/runtime/templates/CLAUDE.md" "$dest_root/CLAUDE.md"
fi

# Initialize empty history / artifacts.
mkdir -p "$dest_goalspec/history" "$dest_goalspec/artifacts"

echo "goalspec: initialized $dest_goalspec"
echo "  project root: $dest_root"
echo "next step: .goalspec/goalspec status"
