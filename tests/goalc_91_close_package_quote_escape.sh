#!/usr/bin/env bash
# GOALC #91: close-package.yaml goal_summary survives quote/colon/hash/backslash
#            injection. goal_summary comes straight from goal.md Intent (user
#            prose) and used to be heredoc'd into a double-quoted YAML scalar
#            with no escaping — an ASCII double-quote in the Intent broke the
#            parse and silently nulled close_package_hash (velentrade v0006
#            close-package incident). The fix routes goal_summary through the
#            strenv scalar helper so arbitrary prose round-trips safely.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-91
"$REPO_GS" new-goal "test" >/dev/null

# Hostile Intent line: CJK + ASCII double-quotes + colon + hash + backslash.
# Every one of these would break a naive  goal_summary: "$x"  heredoc line.
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal

## 1. Intent
直接买入"foo"模拟 a:b 命令 #注入 back\slash 结束

## 2. Narrative
Player loads page, action happens, expected outcome.

## 3. Success Model
- user_visible_success: visible effect
- system_observable_success: state change
- must_not_happen: bad thing
- minimum_acceptable_result: core path
- final_completion_signal: all paths green

## 4. Scope
- in_scope: core feature
- out_of_scope: extras

## 5. Risk Scan
- scope-boundary: clear
- actor-permission: none
- data-lifecycle: in-memory
- failure-degradation: graceful
- non-functional-baseline: acceptable
- integration-boundary: none

## 6. Goal Constraints
none

## 7. Sources and Decisions
- sources: human input
- confirmed_decisions: none
- assumptions: standard env

## 8. Open Questions

## 9. Reopen Triggers
MD

approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p91"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: false
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"
for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "test criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML

"$REPO_GS" run >/dev/null
cpf="$REPO/.goalspec/active/close-package.yaml"

# 1. python yaml parses the file without exception (the original failure mode:
#    ASCII double-quote inside a double-quoted scalar broke parsing).
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$cpf" \
  && ok "close-package.yaml parses with hostile goal_summary" \
  || bad "close-package.yaml failed to parse"

# 2. goal_summary round-trips intact.
got="$(yq e '.goal_summary' "$cpf")"
[ "$got" = '直接买入"foo"模拟 a:b 命令 #注入 back\slash 结束' ] \
  && ok "goal_summary round-trips quote/colon/hash/backslash verbatim" \
  || bad "goal_summary mangled: got=$got"

# 3. close_package_hash is non-empty (the silent-null failure mode).
[ "$(yq e '.hashes.close_package_hash // ""' "$cpf")" != "null" ] \
  && [ -n "$(yq e '.hashes.close_package_hash // ""' "$cpf")" ] \
  && ok "close_package_hash non-empty despite hostile goal_summary" \
  || bad "close_package_hash null/empty"

[ "$TESTS_FAIL" -eq 0 ]
