#!/usr/bin/env bash
# GOALC #100: freeze emits non-blocking BUDGET_WARNING / RUNTIME_EVIDENCE_WARNING
#             from the evidence_requirement runtime_boundary mix + criteria kind,
#             so the human can split the goal or plan staged deployment BEFORE
#             the run burns the context budget. Advisory only — freeze succeeds.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$TESTS_TMP_ROOT/p100"; mkdir -p "$tmp"
printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$tmp/review.yaml"

# --- Case 1: all-runtime evidence -> BUDGET_WARNING, freeze still ok. ---
fresh_initialized_repo goalc-100-c1
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"      # Narrative mentions page/user
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"  # EVIDREQ-001 runtime_boundary: browser
"$REPO_GS" review apply "$tmp/review.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
c1="$("$REPO_GS" freeze 2>&1)"
printf '%s' "$c1" | grep -q 'BUDGET_WARNING.*runtime' && ok "case1: all-runtime evidence triggers BUDGET_WARNING" || bad "case1: BUDGET_WARNING missing: $c1"
printf '%s' "$c1" | grep -q 'contract frozen' && ok "case1: freeze still succeeds despite advisory" || bad "case1: freeze blocked by advisory"

# --- Case 2: all-unit evidence + user-behavior goal -> RUNTIME_EVIDENCE_WARNING. ---
fresh_initialized_repo goalc-100-c2
"$REPO_GS" new-goal "test" >/dev/null
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal
## 1. Intent
用户登录后看到仪表盘。
## 2. Narrative
用户登录 -> 渲染仪表盘页面。
## 3. Success Model
- user_visible_success: dashboard renders
## 4. Scope
- in_scope: login + dashboard
## 5. Risk Scan
- scope-boundary: clear
## 6. Goal Constraints
none
## 7. Sources and Decisions
- sources: human
## 8. Open Questions
## 9. Reopen Triggers
MD
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    statement: login flow observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: unit
    statement: unit-level check
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
"$REPO_GS" review apply "$tmp/review.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
c2="$("$REPO_GS" freeze 2>&1)"
printf '%s' "$c2" | grep -q 'RUNTIME_EVIDENCE_WARNING' && ok "case2: all-unit evidence + user-behavior goal triggers RUNTIME_EVIDENCE_WARNING" || bad "case2: RUNTIME_EVIDENCE_WARNING missing: $c2"
printf '%s' "$c2" | grep -q 'contract frozen' && ok "case2: freeze still succeeds" || bad "case2: freeze blocked by advisory"

# --- Case 3: all-unit evidence + pure-compute goal -> NO difficulty warning. ---
fresh_initialized_repo goalc-100-c3
"$REPO_GS" new-goal "test" >/dev/null
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal
## 1. Intent
CLI computes hash digest of stdin.
## 2. Narrative
read stdin, apply algorithm, emit digest.
## 3. Success Model
- system_observable_success: digest matches expected
## 4. Scope
- in_scope: hash function
## 5. Risk Scan
- scope-boundary: clear
## 6. Goal Constraints
none
## 7. Sources and Decisions
- sources: human
## 8. Open Questions
## 9. Reopen Triggers
MD
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    statement: digest matches golden vector
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    statement: final pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: unit
    statement: golden vector unit test
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
"$REPO_GS" review apply "$tmp/review.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
c3="$("$REPO_GS" freeze 2>&1)"
if printf '%s' "$c3" | grep -qE 'BUDGET_WARNING|RUNTIME_EVIDENCE_WARNING'; then
  bad "case3: pure-compute goal should emit no difficulty warning: $c3"
else
  ok "case3: pure-compute unit goal emits no difficulty warning"
fi

[ "$TESTS_FAIL" -eq 0 ]
