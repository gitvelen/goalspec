#!/usr/bin/env bash
# GOALC #68: goal.md may group sections under optional `### Workunit:` headings
# for readability and criteria traceability. This must NOT break the goal.md
# schema (workunit is a documentation grouping only, never an execution unit);
# criteria may carry an optional `workunit` traceability field that freeze
# accepts, and the prompt must declare workunits are not execution units.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# --- Branch A: flat goal.md (no workunits) still compiles ------------------
fresh_initialized_repo goalc-68-flat
"$REPO_GS" start "flat goal no workunits" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Flat goal.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null \
  && ok "flat goal.md (no workunits) passes schema and compiles" \
  || bad "flat goal.md failed schema/compile"

# --- Branch B: goal.md WITH `### Workunit:` headings + criteria workunit ----
fresh_initialized_repo goalc-68-workunit
"$REPO_GS" start "goal with workunit grouping" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Goal with workunit grouping.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null
cat > "$REPO/.goalspec/active/goal.md" <<'MD'
# Goal

## 1. Intent
Feature with auth and authorization slices.

## 2. Narrative
User signs in, then accesses scoped resources.

## 3. Success Model
### Workunit: 认证
- user_visible_success: 用户可用邮箱密码登录
- must_not_happen: 密码出现在日志
### Workunit: 授权
- user_visible_success: 普通用户被拒绝访问 admin 接口
- final_completion_signal: 角色权限矩阵全绿

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
"$REPO_GS" compile >/dev/null \
  && ok "goal.md with `### Workunit:` headings passes schema and compiles" \
  || bad "goal.md with workunit headings failed schema/compile"

# Overwrite the draft contract with criteria carrying an optional workunit field.
cat > "$REPO/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    workunit: 认证
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    workunit: 授权
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
tmp="$TESTS_TMP_ROOT/c68"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null \
  && ok "freeze accepts criteria with optional workunit field" \
  || bad "freeze rejected criteria with optional workunit field"

# Anti-drift: the prompt must state workunits are NOT execution units.
prompt="$REPO/.goalspec/active/goal-driven-prompt.md"
/bin/grep -q 'NOT execution units' "$prompt" \
  && ok "prompt declares workunits are not execution units" \
  || bad "prompt missing workunit anti-drift declaration"

[ "$TESTS_FAIL" -eq 0 ]
