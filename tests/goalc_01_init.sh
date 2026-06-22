#!/usr/bin/env bash
# GOALC #1: empty git repo + goalspec init -> full .goalspec/, managed AGENTS/CLAUDE,
#            and `goalspec status` gives a clear NEXT_ACTION.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

assert_managed_ai_guide() {
  local file="$1"
  /bin/grep -q '<!-- GOALSPEC:BEGIN -->' "$file" || bad "$file missing managed begin marker"
  /bin/grep -q '<!-- GOALSPEC:END -->' "$file" || bad "$file missing managed end marker"
  /bin/grep -q 'Scope And Priority' "$file" || bad "$file missing scope/priority section"
  /bin/grep -q 'Human Command Map' "$file" || bad "$file missing command map section"
  /bin/grep -q 'Criteria Review Minimum' "$file" || bad "$file missing criteria review minimum"
  /bin/grep -q '.goalspec/ai/core.md' "$file" || bad "$file missing core role instruction"
  /bin/grep -q 'constraint-suggestions.yaml' "$file" || bad "$file missing constraint suggestions flow"
  /bin/grep -q 'approve intake-package' "$file" || bad "$file missing intake package approval"
  /bin/grep -q 'intake apply-suggestions' "$file" || bad "$file missing apply suggestions command"
  /bin/grep -q 'goalspec close' "$file" || bad "$file missing close command"
}

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
assert_managed_ai_guide "$REPO/AGENTS.md"
assert_managed_ai_guide "$REPO/CLAUDE.md"

# status must give a NEXT_USER_ACTION line that points at start (no active goal yet).
status_out="$("$REPO_GS" status)"
echo "$status_out" | /bin/grep -q '^NEXT_USER_ACTION:' || bad "status missing NEXT_USER_ACTION"
echo "$status_out" | /bin/grep -qi '/goalspec start'   || bad "NEXT_USER_ACTION does not mention /goalspec start"

# Re-running init on an installed project is an explicit update flow:
# no confirmation -> refused; "y" -> update runtime/ai/dispatcher but preserve state.
echo "CUSTOM-GOAL" > "$REPO/.goalspec/active/goal.md"
echo "custom-memory: keep" > "$REPO/.goalspec/project/memory.yaml"
echo "old runtime marker" > "$REPO/.goalspec/runtime/OLD_MARKER"
echo "old ai marker" > "$REPO/.goalspec/ai/OLD_MARKER"
rm -rf "$REPO/.goalspec/skills"
cat > "$REPO/AGENTS.md" <<'MD'
# Goalspec

本项目使用 Goalspec 框架管理目标驱动的开发。

开始任务前运行或读取 `.goalspec/goalspec status`，按 `NEXT_ACTION` 加载对应角色指令。
会话录入结束后，先写 `active/intake-capture.md` 并取得 `goalspec approve intake-capture`，再写 `active/goal.md`。
不要自评完成。
MD
cp "$REPO/AGENTS.md" "$REPO/CLAUDE.md"

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
assert_managed_ai_guide "$REPO/AGENTS.md"
assert_managed_ai_guide "$REPO/CLAUDE.md"
if /bin/grep -q 'approve intake-capture' "$REPO/AGENTS.md" || /bin/grep -q 'approve intake-capture' "$REPO/CLAUDE.md"; then
  bad "init update preserved stale approve intake-capture guidance"
else
  ok "init update replaces legacy Goalspec AI guide"
fi

fresh_repo goalc-01-custom-guide
cat > "$REPO/AGENTS.md" <<'MD'
# Project Agents

Keep existing project-specific guidance.
MD
cp "$REPO/AGENTS.md" "$REPO/CLAUDE.md"
( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ) || bad "custom guide init failed"
/bin/grep -q 'Keep existing project-specific guidance.' "$REPO/AGENTS.md" \
  || bad "custom AGENTS.md content was not preserved"
/bin/grep -q 'Keep existing project-specific guidance.' "$REPO/CLAUDE.md" \
  || bad "custom CLAUDE.md content was not preserved"
assert_managed_ai_guide "$REPO/AGENTS.md"
assert_managed_ai_guide "$REPO/CLAUDE.md"
before_count="$(/bin/grep -c '<!-- GOALSPEC:BEGIN -->' "$REPO/AGENTS.md")"
printf 'y\n' | ( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ) || bad "custom guide update failed"
after_count="$(/bin/grep -c '<!-- GOALSPEC:BEGIN -->' "$REPO/AGENTS.md")"
[ "$before_count" = "1" ] && [ "$after_count" = "1" ] \
  && ok "managed Goalspec guide update is idempotent" \
  || bad "managed Goalspec guide duplicated on update"

fresh_repo goalc-01-malformed-guide
cat > "$REPO/AGENTS.md" <<'MD'
# Project Agents

<!-- GOALSPEC:BEGIN -->
broken managed block without an end marker
MD
cp "$REPO/AGENTS.md" "$REPO/CLAUDE.md"
( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ) || bad "malformed guide init failed"
before_hash="$(sha256sum "$REPO/AGENTS.md" | awk '{print $1}')"
err="$(printf 'y\n' | ( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ) 2>&1 || true)"
after_hash="$(sha256sum "$REPO/AGENTS.md" | awk '{print $1}')"
[ "$before_hash" = "$after_hash" ] \
  && ok "malformed managed Goalspec guide is left unchanged" \
  || bad "malformed managed Goalspec guide was modified"
echo "$err" | /bin/grep -q 'managed Goalspec block' \
  && ok "malformed managed Goalspec guide emits warning" \
  || bad "malformed managed Goalspec guide did not warn"

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
[ -f "$ai_home/plugins/goalspec/commands/goalspec.md" ] \
  && /bin/grep -q 'Run a Goalspec project-local lifecycle command' "$ai_home/plugins/goalspec/commands/goalspec.md" \
  && ok "install-ai codex installs slash command" \
  || bad "install-ai codex did not install slash command"
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
