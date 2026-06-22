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
  mkdir -p "$plugin_root/.codex-plugin" "$plugin_root/skills/goalspec" "$plugin_root/commands" "$(dirname "$marketplace")"
  cp -R "$SRC_ROOT/skills/goalspec/." "$plugin_root/skills/goalspec/"
  cat > "$plugin_root/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "goalspec",
  "version": "0.1.0",
  "description": "Goalspec project-local goal-driven development workflow",
  "author": {
    "name": "Goalspec"
  },
  "keywords": ["goalspec", "goal", "contract", "intake"],
  "skills": "./skills/",
  "interface": {
    "displayName": "Goalspec",
    "shortDescription": "Run project-local goal-driven development workflows.",
    "longDescription": "Goalspec adds an explicit, project-local lifecycle for goal capture, frozen criteria, implementation, verification, and closeout.",
    "developerName": "Goalspec",
    "category": "Productivity",
    "capabilities": ["Interactive", "Write"],
    "defaultPrompt": [
      "Run /goalspec status",
      "Start a Goalspec-managed change"
    ],
    "brandColor": "#2563EB"
  }
}
JSON
  cat > "$plugin_root/commands/goalspec.md" <<'MD'
---
description: Run a Goalspec project-local lifecycle command.
---

# Goalspec

Interpret this slash command as the human-facing Goalspec command layer. Execute the matching project-local `.goalspec/goalspec ...` command only as a direct translation of the human's `/goalspec ...` input.

Goalspec is explicit opt-in: only enter this lifecycle when the human explicitly uses `/goalspec ...` or clearly asks to run a formal Goalspec-managed change. Otherwise handle the request as normal development work.

Supported human-facing commands:

- `/goalspec status`
- `/goalspec start <intent>`
- `/goalspec source <path>`
- `/goalspec end`
- `/goalspec run`
- `/goalspec close`
- `/goalspec reopen <reason>`

Before lifecycle actions, run `.goalspec/goalspec status` and follow the installed `goalspec` skill's command map. Do not treat bare "确认", "ok", "continue", or silence as run, freeze, or close permission.
MD
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
Use the bundled goalspec skill. Interpret `/goalspec ...` as the human-facing Goalspec command layer; execute `.goalspec/goalspec ...` only as the project-local agent CLI translation.

Goalspec is explicit opt-in: only enter this lifecycle when the human explicitly uses `/goalspec ...` or clearly asks to run a formal Goalspec-managed change. Otherwise handle the request as normal development work.
MD
  echo "goalspec Claude plugin package installed: $plugin_root"
}

install_lingma_commands() {
  local commands_dir
  commands_dir="$HOME/.lingma/commands"
  mkdir -p "$commands_dir"
cat > "$commands_dir/goalspec.md" <<'MD'
# Goalspec

Use the installed goalspec skill. Interpret `/goalspec status`, `/goalspec start`, `/goalspec source`, `/goalspec end`, `/goalspec run`, `/goalspec close`, and `/goalspec reopen` as the human-facing Goalspec command layer; execute `.goalspec/goalspec ...` only as the project-local agent CLI translation.

Goalspec is explicit opt-in: only enter this lifecycle when the human explicitly uses `/goalspec ...` or clearly asks to run a formal Goalspec-managed change. Otherwise handle the request as normal development work.

`/goalspec start` opens the formal intake window only when status is `no_goal` or `closed`. `/goalspec source <path>` only adds material while the window is open (collecting). `/goalspec end` is the only command that closes the window, after which the AI must draft a concise Goal / Criteria / Constraints review summary and wait for `确认并冻结契约` before freezing. Do not start implementation unless the user explicitly runs `/goalspec run`.

## Run hard rules

When the user runs `/goalspec run`:

1. Run `.goalspec/goalspec run`.
2. If it prints `GOALSPEC_RUN_ALLOWED: false`, stop immediately.
3. If it prints `GOALSPEC_RUN_ALLOWED: true`, read `.goalspec/active/goal-driven-prompt.md` in full before modifying any business code.
4. Treat the Prompt's Goal, Criteria, and Constraints as the authoritative control for this execution.
5. Do not substitute your own implementation plan for this Prompt. Do not execute from memory.
6. Do not continue if the Prompt is missing, stale, or not frozen.
7. Never treat bare "confirm", "确认", "ok", or "continue" as run, freeze, or close permission. Require stage-specific phrases such as `确认并应用 intake package` or `确认并冻结契约`, and require `/goalspec run` for implementation.

If the tool supports explicit subagents, create exactly one Subagent to execute; otherwise simulate role separation with visible `Master Evaluation`, `Subagent Work`, and `Evidence/Progress Report` phases. Do not self-declare completion — Criteria completion only comes from Master verdicts, and delivery closure only comes from a successful `.goalspec/goalspec close` using the configured delivery mode. Do not manually replace close with git/gh/archive/state edits.
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
