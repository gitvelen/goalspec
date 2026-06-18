#!/usr/bin/env bash
# install_skill.sh — install bundled Goalspec AI skill for compatible tools.
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

dest="${GOALSPEC_SKILL_DIR:-$HOME/.agents/skills/goalspec}"
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
usage: goalspec install-skill [destination-dir]

Installs the bundled Goalspec skill to:
  ~/.agents/skills/goalspec

Override with an explicit destination or GOALSPEC_SKILL_DIR.
EOF
  exit 0
fi

if [ $# -ge 1 ]; then
  dest="$1"
fi

src="$SRC_ROOT/skills/goalspec"
[ -f "$src/SKILL.md" ] || { echo "goalspec install-skill: bundled skill missing: $src/SKILL.md" >&2; exit 1; }

mkdir -p "$dest"
cp -R "$src/." "$dest/"

echo "goalspec skill installed: $dest/SKILL.md"
echo "next: restart or reload your AI tool so it discovers the skill"
