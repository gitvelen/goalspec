#!/usr/bin/env bash
# GOALC #44: every AI adapter template carries the hard "human-gated commands"
#            rule (start/end/run/close executed only on the user's explicit
#            slash-command, never self-initiated by the agent). Guards against
#            the rule being silently dropped by a future "maintain generated
#            guides" pass — the gap that let an agent auto-run `intake end`.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

T="$FRAMEWORK/runtime/templates"
S="$FRAMEWORK/skills/goalspec"

# English adapter docs must (a) name the gates, (b) forbid self-initiation, and
# (c) explicitly forbid executing `intake end` (the exact command that was abused).
for f in "$T/AGENTS.md" "$T/CLAUDE.md"; do
  grep -q '人类门禁' "$f"             && ok "$f names the human gates"         || bad "$f missing '人类门禁'"
  grep -q '绝不自启' "$f"             && ok "$f forbids self-initiation"      || bad "$f missing '绝不自启'"
  grep -q 'goalspec intake end' "$f"  && ok "$f names the intake-end command" || bad "$f missing 'intake end' naming"
done

# core.md (Chinese) carries the equivalent rule.
grep -q '人类门禁' "$T/ai/core.md"   && ok "core.md names 人类门禁"            || bad "core.md missing 人类门禁"
grep -q '绝不自启' "$T/ai/core.md"   && ok "core.md forbids 自启"              || bad "core.md missing 绝不自启"

# Skill + command-map carry the gate summary.
grep -qi 'never self-initiate' "$S/SKILL.md"               && ok "SKILL.md forbids self-initiation" || bad "SKILL.md missing gate rule"
grep -qi 'never self-initiated' "$S/references/command-map.md" && ok "command-map.md forbids self-initiation" || bad "command-map.md missing gate note"

# The review gate after /goalspec end must require a stage-specific phrase.
for f in "$T/AGENTS.md" "$T/CLAUDE.md"; do
  grep -q '确认并冻结契约' "$f" \
    && ok "$f requires stage-specific contract freeze confirmation" \
    || bad "$f missing stage-specific contract freeze confirmation"
  grep -q '人类命令' "$f" \
    && grep -q 'Agent CLI 翻译' "$f" \
    && ok "$f separates human commands from agent execution" \
    || bad "$f mixes human commands and agent execution"
done

grep -q '确认并冻结契约' "$S/SKILL.md" \
  && ok "SKILL.md requires stage-specific contract freeze confirmation" \
  || bad "SKILL.md missing stage-specific contract freeze confirmation"
grep -q '确认并应用 intake package' "$S/SKILL.md" \
  && ok "SKILL.md requires stage-specific intake package approval" \
  || bad "SKILL.md missing stage-specific intake package approval"

[ "$TESTS_FAIL" -eq 0 ]
