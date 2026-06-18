#!/usr/bin/env bash
# GOALC #1: empty git repo + goalspec init -> full .goalspec/, short AGENTS/CLAUDE,
#            and `goalspec status` gives a clear NEXT_ACTION.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-01
ok "init in empty git repo"

[ -d "$REPO/.goalspec/runtime" ] || bad "missing runtime/"
[ -d "$REPO/.goalspec/ai" ]       || bad "missing ai/"
[ -d "$REPO/.goalspec/project" ]  || bad "missing project/"
[ -d "$REPO/.goalspec/active" ]   || bad "missing active/"
[ -f "$REPO/.goalspec/skills/goalspec/SKILL.md" ] || bad "missing bundled goalspec skill"
[ -f "$REPO/AGENTS.md" ]          || bad "missing AGENTS.md"
[ -f "$REPO/CLAUDE.md" ]          || bad "missing CLAUDE.md"
[ -x "$REPO_GS" ]                 || bad "goalspec not executable"

# status must give a NEXT_ACTION line that points at new-goal (no active goal yet).
status_out="$("$REPO_GS" status)"
echo "$status_out" | /bin/grep -q '^NEXT_ACTION:' || bad "status missing NEXT_ACTION"
echo "$status_out" | /bin/grep -qi 'new-goal'     || bad "NEXT_ACTION does not mention new-goal"

# Re-running init on an installed project is an explicit update flow:
# no confirmation -> refused; "y" -> update runtime/ai/dispatcher but preserve state.
echo "CUSTOM-GOAL" > "$REPO/.goalspec/active/goal.md"
echo "custom-memory: keep" > "$REPO/.goalspec/project/memory.yaml"
echo "old runtime marker" > "$REPO/.goalspec/runtime/OLD_MARKER"
echo "old ai marker" > "$REPO/.goalspec/ai/OLD_MARKER"
rm -rf "$REPO/.goalspec/skills"

if ( cd "$REPO" && bash "$FRAMEWORK/goalspec" init </dev/null >/dev/null 2>&1 ); then
  bad "init update succeeded without confirmation"
else
  ok "init update refused without confirmation"
fi

if printf 'y\n' | ( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ); then
  ok "init update accepted with y confirmation"
else
  bad "init update failed with y confirmation"
fi

[ -f "$REPO/.goalspec/active/goal.md" ] && /bin/grep -q 'CUSTOM-GOAL' "$REPO/.goalspec/active/goal.md" \
  || bad "init update did not preserve active goal.md"
[ -f "$REPO/.goalspec/project/memory.yaml" ] && /bin/grep -q 'custom-memory: keep' "$REPO/.goalspec/project/memory.yaml" \
  || bad "init update did not preserve project memory"
[ ! -f "$REPO/.goalspec/runtime/OLD_MARKER" ] \
  || bad "init update did not replace runtime"
[ ! -f "$REPO/.goalspec/ai/OLD_MARKER" ] \
  || bad "init update did not replace ai role templates"
[ -f "$REPO/.goalspec/active/intake-capture.md" ] \
  || bad "init update did not add missing intake-capture template"
[ -f "$REPO/.goalspec/skills/goalspec/SKILL.md" ] \
  || bad "init update did not restore bundled goalspec skill"

skill_dest="$TESTS_TMP_ROOT/installed-skill"
"$REPO_GS" install-skill "$skill_dest" >/dev/null
[ -f "$skill_dest/SKILL.md" ] && /bin/grep -q '^name: goalspec' "$skill_dest/SKILL.md" \
  && ok "install-skill installs bundled skill" \
  || bad "install-skill did not install bundled skill"
[ -f "$skill_dest/references/constraint-extraction.md" ] \
  && ok "install-skill installs bundled skill references" \
  || bad "install-skill did not install bundled skill references"

ai_home="$TESTS_TMP_ROOT/ai-home"
HOME="$ai_home" "$REPO_GS" install-ai codex >/dev/null
[ -f "$ai_home/.codex/skills/goalspec/SKILL.md" ] \
  && ok "install-ai codex installs Codex skill" \
  || bad "install-ai codex did not install Codex skill"
[ -f "$ai_home/plugins/goalspec/.codex-plugin/plugin.json" ] \
  && ok "install-ai codex installs local plugin package" \
  || bad "install-ai codex did not install local plugin package"
[ -f "$ai_home/.agents/plugins/marketplace.json" ] \
  && yq e '.plugins[] | select(.name == "goalspec") | .category' "$ai_home/.agents/plugins/marketplace.json" | /bin/grep -q 'Productivity' \
  && ok "install-ai codex updates personal marketplace" \
  || bad "install-ai codex did not update personal marketplace"

HOME="$ai_home" "$REPO_GS" install-ai claude >/dev/null
[ -f "$ai_home/.claude/skills/goalspec/SKILL.md" ] && [ -f "$ai_home/.claude/plugins/goalspec-local/.claude-plugin/plugin.json" ] \
  && ok "install-ai claude installs skill and plugin package" \
  || bad "install-ai claude did not install skill and plugin package"

HOME="$ai_home" "$REPO_GS" install-ai lingma >/dev/null
[ -f "$ai_home/.lingma/skills/goalspec/SKILL.md" ] && [ -f "$ai_home/.lingma/commands/goalspec.md" ] \
  && ok "install-ai lingma installs skill and command notes" \
  || bad "install-ai lingma did not install skill and command notes"

[ "$TESTS_FAIL" -eq 0 ]
