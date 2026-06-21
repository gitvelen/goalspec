#!/usr/bin/env bash
# GOALC #46: adapter and skill docs describe Goalspec as explicit opt-in, so
#            normal project work does not silently enter the lifecycle just
#            because .goalspec exists.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

T="$FRAMEWORK/runtime/templates"
S="$FRAMEWORK/skills/goalspec"
I="$FRAMEWORK/runtime/commands/install_ai.sh"
R="$FRAMEWORK/README.md"

for f in "$T/AGENTS.md" "$T/CLAUDE.md"; do
  grep -qi 'explicit opt-in' "$f" && ok "$f says explicit opt-in" || bad "$f missing explicit opt-in"
  grep -qi 'do not self-upgrade casual requests' "$f" && ok "$f forbids self-upgrade" || bad "$f missing self-upgrade rule"
done

grep -q '显式启用' "$T/ai/core.md" && ok "core.md says 显式启用" || bad "core.md missing 显式启用"
grep -q '普通问答、调试、小修或一次性工作默认不走框架' "$T/ai/core.md" \
  && ok "core.md says normal work stays outside Goalspec" \
  || bad "core.md missing normal-work rule"

grep -qi 'explicit opt-in' "$S/SKILL.md" && ok "SKILL.md says explicit opt-in" || bad "SKILL.md missing explicit opt-in"
grep -qi 'Requests that do not explicitly enter Goalspec' "$S/SKILL.md" \
  && ok "SKILL.md says non-opt-in requests stay normal" \
  || bad "SKILL.md missing non-opt-in rule"

grep -qi 'explicit opt-in' "$S/references/command-map.md" && ok "command-map says explicit opt-in" || bad "command-map missing explicit opt-in"
grep -qi 'Otherwise handle the request as normal development work' "$I" && ok "install_ai docs keep normal work outside Goalspec" || bad "install_ai missing opt-in rule"
grep -q '## When Goalspec applies' "$R" && ok "README has When Goalspec applies" || bad "README missing opt-in section"
grep -q 'reopen-impact.yaml' "$R" && ok "README documents reopen-impact.yaml" || bad "README missing reopen-impact.yaml"
grep -q 'Delivery modes' "$R" && ok "README documents delivery modes" || bad "README missing delivery modes"
grep -q 'delivery.mode' "$R" && ok "README documents delivery.mode" || bad "README missing delivery.mode"
for f in "$T/AGENTS.md" "$T/CLAUDE.md"; do
  grep -q 'configured delivery mode' "$f" && ok "$f mentions configured delivery mode" || bad "$f missing configured delivery mode"
done

[ "$TESTS_FAIL" -eq 0 ]
