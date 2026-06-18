#!/usr/bin/env bash
# install_ai.sh — install Goalspec AI adapters for specific tools.
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tool="${1:-}"
shift || true

# Resolve yq (system mikefarah v4, else vendored binary) before the yq use
# further down — this command must work on targets without yq installed.
# shellcheck disable=SC1091
. "$SRC_ROOT/runtime/lib/yq.sh"
goalspec_setup_yq "$SRC_ROOT" || exit 1

usage() {
  cat <<'EOF'
usage: goalspec install-ai <codex|claude|lingma> [--kind skill|plugin|both]

Installs Goalspec AI tool adapters:
  codex   -> ~/.codex/skills/goalspec plus a local Codex plugin package
  claude  -> ~/.claude/skills/goalspec plus a local Claude plugin package
  lingma  -> ~/.lingma/skills/goalspec plus custom command notes
EOF
}

[ "$tool" = "--help" ] || [ "$tool" = "-h" ] && { usage; exit 0; }
[ -n "$tool" ] || { usage >&2; exit 2; }

kind="both"
while [ $# -gt 0 ]; do
  case "$1" in
    --kind)
      [ $# -ge 2 ] || { echo "goalspec install-ai: --kind requires skill|plugin|both" >&2; exit 2; }
      kind="$2"; shift 2
      ;;
    *)
      echo "goalspec install-ai: unknown option $1" >&2
      exit 2
      ;;
  esac
done

case "$kind" in skill|plugin|both) ;; *) echo "goalspec install-ai: invalid --kind $kind" >&2; exit 2 ;; esac

copy_skill() {
  local dest="$1"
  mkdir -p "$dest"
  cp -R "$SRC_ROOT/skills/goalspec/." "$dest/"
  echo "goalspec skill installed: $dest/SKILL.md"
}

install_codex_plugin() {
  local plugin_root marketplace
  plugin_root="$HOME/plugins/goalspec"
  marketplace="$HOME/.agents/plugins/marketplace.json"
  mkdir -p "$plugin_root/.codex-plugin" "$plugin_root/skills/goalspec" "$(dirname "$marketplace")"
  cp -R "$SRC_ROOT/skills/goalspec/." "$plugin_root/skills/goalspec/"
  cat > "$plugin_root/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "goalspec",
  "version": "0.1.0",
  "description": "Goalspec project-local goal-driven development workflow",
  "skills": [
    {
      "name": "goalspec",
      "path": "skills/goalspec"
    }
  ]
}
JSON
  if [ ! -f "$marketplace" ]; then
    cat > "$marketplace" <<'JSON'
{
  "name": "personal",
  "interface": {
    "displayName": "Personal"
  },
  "plugins": []
}
JSON
  fi
  tmp="$(mktemp)"
  yq -o=json e ".plugins = ([.plugins[] | select(.name != \"goalspec\")] + [{\"name\":\"goalspec\",\"source\":{\"source\":\"local\",\"path\":\"./plugins/goalspec\"},\"policy\":{\"installation\":\"AVAILABLE\",\"authentication\":\"ON_INSTALL\"},\"category\":\"Productivity\"}])" "$marketplace" > "$tmp"
  mv "$tmp" "$marketplace"
  echo "goalspec Codex plugin package installed: $plugin_root"
  echo "goalspec Codex marketplace updated: $marketplace"
}

install_claude_plugin() {
  local plugin_root
  plugin_root="$HOME/.claude/plugins/goalspec-local"
  mkdir -p "$plugin_root/.claude-plugin" "$plugin_root/skills/goalspec" "$plugin_root/commands"
  cp -R "$SRC_ROOT/skills/goalspec/." "$plugin_root/skills/goalspec/"
  cat > "$plugin_root/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "goalspec",
  "description": "Goalspec project-local goal-driven development workflow",
  "version": "0.1.0",
  "author": {
    "name": "Goalspec"
  },
  "keywords": ["goalspec", "goal", "contract", "intake"]
}
JSON
  cat > "$plugin_root/marketplace.json" <<'JSON'
{
  "name": "goalspec-local",
  "description": "Local Goalspec plugin marketplace",
  "plugins": [
    {
      "name": "goalspec",
      "description": "Goalspec project-local goal-driven development workflow",
      "version": "0.1.0",
      "source": "./"
    }
  ]
}
JSON
  cat > "$plugin_root/commands/goalspec.md" <<'MD'
Use the bundled goalspec skill. Interpret `/goalspec ...` as the user-facing Goalspec command layer and follow the project-local `.goalspec/goalspec status` output.
MD
  echo "goalspec Claude plugin package installed: $plugin_root"
}

install_lingma_commands() {
  local commands_dir
  commands_dir="$HOME/.lingma/commands"
  mkdir -p "$commands_dir"
cat > "$commands_dir/goalspec.md" <<'MD'
# Goalspec

Use the installed goalspec skill. Interpret `/goalspec status`, `/goalspec start`, `/goalspec source`, `/goalspec end`, `/goalspec run`, and `/goalspec reopen` as the user-facing Goalspec command layer. Do not start implementation unless the user explicitly runs `/goalspec run`.
MD
  echo "goalspec Lingma command notes installed: $commands_dir/goalspec.md"
}

case "$tool" in
  codex)
    [ "$kind" = "plugin" ] || copy_skill "${CODEX_HOME:-$HOME/.codex}/skills/goalspec"
    [ "$kind" = "skill" ] || install_codex_plugin
    ;;
  claude)
    [ "$kind" = "plugin" ] || copy_skill "$HOME/.claude/skills/goalspec"
    [ "$kind" = "skill" ] || install_claude_plugin
    ;;
  lingma)
    [ "$kind" = "plugin" ] || copy_skill "$HOME/.lingma/skills/goalspec"
    [ "$kind" = "skill" ] || install_lingma_commands
    ;;
  *)
    echo "goalspec install-ai: unsupported tool '$tool' (expected codex, claude, or lingma)" >&2
    exit 2
    ;;
esac

echo "next: restart or reload $tool so it discovers Goalspec"
