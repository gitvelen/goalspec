#!/usr/bin/env bash
# GOALC #60: a criteria-WRITING skill lives in the goalspec skill bundle and is
#            wired into compiler.md + SKILL.md, so Criteria are drafted via a
#            structured product-coverage / engineering / testing / verifiability
#            procedure at generation time (not only caught downstream by review).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CW="$FRAMEWORK/skills/goalspec/references/criteria-writing.md"
COMP="$FRAMEWORK/runtime/templates/ai/compiler.md"
SKILL="$FRAMEWORK/skills/goalspec/SKILL.md"
INSTALL="$FRAMEWORK/runtime/commands/install_skill.sh"

# 1. The methodology reference exists and carries the four lenses + examples.
[ -f "$CW" ] && ok "criteria-writing.md exists" || bad "criteria-writing.md missing"
grep -q '产品覆盖' "$CW"   && ok "criteria-writing has product-coverage lens"  || bad "criteria-writing missing product-coverage lens"
grep -q '工程专家' "$CW"   && ok "criteria-writing has engineering lens"       || bad "criteria-writing missing engineering lens"
grep -q '测试专家' "$CW"   && ok "criteria-writing has testing lens"           || bad "criteria-writing missing testing lens"
grep -q '可验收性' "$CW"   && ok "criteria-writing has verifiability lens"     || bad "criteria-writing missing verifiability lens"
grep -q 'loop-safety' "$CW" && ok "criteria-writing has loop-safety check"     || bad "criteria-writing missing loop-safety check"
grep -q 'must_not_happen' "$CW" && ok "criteria-writing maps must_not_happen -> negative" || bad "criteria-writing missing must_not_happen rule"
grep -q 'final: true' "$CW" && ok "criteria-writing maps final_completion_signal -> final" || bad "criteria-writing missing final rule"
grep -q '好坏示例' "$CW"   && ok "criteria-writing has good/bad examples"      || bad "criteria-writing missing examples"
grep -q 'Bad' "$CW" && grep -q 'Good' "$CW" && ok "criteria-writing shows bad vs good" || bad "criteria-writing missing bad/good contrast"

# 2. compiler.md no longer relies on the old single-line hint; it points to the
#    skill and names the four lenses inline (works even if the skill is absent).
grep -q 'references/criteria-writing.md' "$COMP" && ok "compiler.md points to criteria-writing skill" || bad "compiler.md missing criteria-writing pointer"
grep -q '产品覆盖' "$COMP" && ok "compiler.md inlines product-coverage lens"   || bad "compiler.md missing product-coverage lens"
grep -q '工程有效性' "$COMP" && ok "compiler.md inlines engineering lens"      || bad "compiler.md missing engineering lens"
grep -q '测试覆盖' "$COMP" && ok "compiler.md inlines testing lens"            || bad "compiler.md missing testing lens"
grep -q '可验收性' "$COMP" && ok "compiler.md inlines verifiability lens"      || bad "compiler.md missing verifiability lens"

# 3. SKILL.md surfaces the methodology at the compile/Criteria-drafting moment.
grep -q 'references/criteria-writing.md' "$SKILL" && ok "SKILL.md points to criteria-writing" || bad "SKILL.md missing criteria-writing pointer"
grep -q 'Criteria Drafting' "$SKILL" && ok "SKILL.md has Criteria Drafting section" || bad "SKILL.md missing Criteria Drafting section"

# 4. install_skill.sh bundles the methodology into the installed skill.
dest="$TESTS_TMP_ROOT/skill-install"
bash "$INSTALL" "$dest" >/dev/null 2>&1 && ok "install_skill.sh runs" || bad "install_skill.sh failed"
[ -f "$dest/references/criteria-writing.md" ] && ok "installed skill bundles criteria-writing.md" || bad "installed skill missing criteria-writing.md"

[ "$TESTS_FAIL" -eq 0 ]
