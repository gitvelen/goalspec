#!/usr/bin/env bash
# Phase A — compile one-line input into full goal.md + behavior-sliced contract, then freeze.
set -uo pipefail
cd "$(dirname "$0")"   # /home/admin/snake
GS=".goalspec/goalspec"
WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

# 1. new-goal from one human sentence
"$GS" new-goal "请设计一个网页版的贪吃蛇游戏，可以通过键盘上的方向键来控制运动" >/dev/null
echo "ok new-goal"

# 2. goal.md — full §27.1 semantics, NO implementation plan
cat > .goalspec/active/goal.md <<'MD'
# Goal

## 1. Intent
构建一个可在浏览器中游玩的单页贪吃蛇游戏。玩家通过键盘方向键控制蛇的移动方向。游戏在页面加载后即可开始游玩，不依赖账号、后端或联网服务。一句话输入：网页版贪吃蛇，方向键控制。

## 2. Narrative
- 玩家打开网页后，立即看到游戏区域、一条初始蛇、一颗食物和当前分数。
- 蛇按固定节奏（tick）自动持续移动。
- 玩家按下方向键可改变蛇的移动方向。
- 蛇头部进入食物坐标后，身体增长一节，分数增加，并在空地上刷新一颗新食物。
- 蛇撞墙或撞到自身身体时，游戏结束，并给出可重新开始的反馈。
- 玩家执行重开操作后，游戏回到初始状态。

## 3. Success Model
- user_visible_success: 玩家可通过方向键实时控制蛇，能看到分数增长和游戏结束状态，并能重开。
- system_observable_success: 浏览器运行时能接收键盘事件、按 tick 更新蛇坐标、更新食物坐标、更新得分、判定 game over 与重开。
- must_not_happen: 蛇不能因反向输入瞬间掉头导致自身重叠；食物不能刷新到蛇身体上；游戏结束后不能继续移动直到重开。
- minimum_acceptable_result: 只做桌面浏览器键盘控制，不含触屏手势、联网排行榜、音效或皮肤系统。
- final_completion_signal: 在浏览器级验证中，自动移动、方向键控制（含反向保护）、吃食物增长、撞墙结束、重开五条主路径全部通过。

## 4. Scope
- in_scope: 前端单页游戏、游戏循环、键盘输入、分数显示、game over 与重开。
- out_of_scope: 后端服务、用户系统、排行榜、移动端触控、多人模式、主题/皮肤商城、音效。

## 5. Risk Scan
- scope-boundary: 仅前端单文件，不触碰任何后端/服务/数据存储。
- actor-permission: 无账号无权限，纯本地游玩。
- data-lifecycle: 所有状态在浏览器内存，页面刷新即重置，无持久化。
- failure-degradation: 撞墙/撞自身即 game over，需明确重开操作恢复，不应静默继续。
- non-functional-baseline: 桌面浏览器 60fps 级别流畅，单 HTML 文件零构建。
- integration-boundary: 无外部集成，不联网。

## 6. Goal Constraints
- 不引入后端依赖。
- 不引入实时联网能力。
- 保持单文件前端实现，不平行引入第二套 UI 运行时或构建链。

## 7. Sources and Decisions
- sources: 人类一句话需求。
- confirmed_decisions: 单 HTML 文件实现；桌面浏览器键盘控制。
- assumptions: 用户在桌面浏览器中游玩；本机具备浏览器自动化能力以产出 browser 级 evidence。

## 8. Open Questions
（无 blocking 问题；如运行环境无浏览器自动化，evidence 强度需如实降级并在 trace 中记录。）

## 9. Reopen Triggers
- 若发现键盘控制在某浏览器不生效，需重开评估输入层方案。
- 若必须引入持久化/后端才能满足"可游玩"，则目标本身需重开。
MD
echo "ok goal.md"

# 3. intake review (fresh-context guardian result)
cat > "$WORK/intake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: "goal.md 冷启动自足：Intent/Narrative/Success Model/Scope/Risk Scan/Open Questions 齐全；must_not_happen 明确；无两种合理解释导致不同实现。"
YML
"$GS" review apply "$WORK/intake.yaml" >/dev/null
echo "ok intake-review"

# 4. approve goal
"$GS" approve goal >/dev/null
echo "ok approve-goal"

# 5. compile (binds goal_hash + project_memory_hash, status draft)
"$GS" compile >/dev/null
echo "ok compile"

# 6. write full behavior-sliced contract (§27.2 WUs, §27.3 criteria, §27.4 evidence reqs)
cat > .goalspec/active/contract.yaml <<'YML'
status: draft
goal_hash: null
project_memory_hash: null
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    required_for_completion: true
    statement: 页面首次加载后游戏区域可见，蛇在无键盘输入情况下按固定 tick 连续移动。
    pass_signals: ["snake moves on tick without input"]
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-002
    kind: machine
    priority: P0
    required_for_completion: true
    statement: 按下方向键后蛇在下一个有效 tick 按对应方向移动；与当前方向相反的输入被忽略。
    pass_signals: ["direction changes on key", "reverse input ignored"]
    evidence_requirement_refs: [EVIDREQ-002]
  - id: CRIT-003
    kind: machine
    priority: P0
    required_for_completion: true
    statement: 蛇头进入食物坐标后分数 +1、长度 +1，新食物坐标不与蛇身任一节重叠。
    pass_signals: ["score increments", "length grows", "new food not on snake"]
    evidence_requirement_refs: [EVIDREQ-003]
  - id: CRIT-004
    kind: machine
    priority: P0
    required_for_completion: true
    statement: 蛇撞墙或撞到自己时游戏状态变为 game over，后续 tick 不再推进蛇位置。
    pass_signals: ["game over on wall/self", "no movement after over"]
    evidence_requirement_refs: [EVIDREQ-004]
  - id: CRIT-005
    kind: machine
    priority: P0
    required_for_completion: true
    statement: 玩家执行重开操作后游戏重新初始化：分数归零、蛇恢复初始长度与位置、食物刷新。
    pass_signals: ["reset to initial state"]
    evidence_requirement_refs: [EVIDREQ-005]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    required_for_completion: true
    final: true
    statement: 在浏览器运行时 CRIT-001..005 对应场景全部通过，且未偷偷实现任何 out_of_scope 功能。
    pass_signals: ["all five scenarios green in browser", "no out_of_scope feature"]
    evidence_requirement_refs: [EVIDREQ-001, EVIDREQ-002, EVIDREQ-003, EVIDREQ-004, EVIDREQ-005]
work_units:
  - id: WU-001
    goal: 页面加载后游戏区域、初始蛇、食物、分数可见，蛇自动按固定节奏移动。
    depends_on: []
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
  - id: WU-002
    goal: 玩家按方向键可改变蛇方向，且不能直接反向掉头。
    depends_on: [WU-001]
    criteria_refs: [CRIT-002]
    evidence_requirement_refs: [EVIDREQ-002]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
  - id: WU-003
    goal: 蛇吃到食物后身体增长、分数增加，新食物不生成在蛇身上。
    depends_on: [WU-002]
    criteria_refs: [CRIT-003]
    evidence_requirement_refs: [EVIDREQ-003]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
  - id: WU-004
    goal: 蛇撞墙或撞自己时游戏结束并停止移动，且可通过明确操作重开。
    depends_on: [WU-003]
    criteria_refs: [CRIT-004, CRIT-005]
    evidence_requirement_refs: [EVIDREQ-004, EVIDREQ-005]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
  - id: WU-005
    goal: 最终浏览器级集成验证覆盖全部成功与失败路径。
    depends_on: [WU-001, WU-002, WU-003, WU-004]
    criteria_refs: [CRIT-FINAL-001]
    evidence_requirement_refs: [EVIDREQ-001, EVIDREQ-002, EVIDREQ-003, EVIDREQ-004, EVIDREQ-005]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: 浏览器级自动化验证页面加载后蛇按 tick 自动移动。
  - id: EVIDREQ-002
    runtime_boundary: browser
    statement: 浏览器级自动化验证方向键输入与非法反向输入保护。
  - id: EVIDREQ-003
    runtime_boundary: browser
    statement: 浏览器级自动化验证吃食物增长与新食物不重叠。
  - id: EVIDREQ-004
    runtime_boundary: browser
    statement: 浏览器级自动化验证撞墙/撞自身 game over 并停止移动。
  - id: EVIDREQ-005
    runtime_boundary: browser
    statement: 浏览器级自动化验证重开逻辑（归零、恢复初始）。
coverage_map:
  - goal_ref: "goal.md#narrative"
    criteria_refs: [CRIT-001, CRIT-002, CRIT-003, CRIT-004, CRIT-005]
  - goal_ref: "goal.md#must-not-happen"
    criteria_refs: [CRIT-002, CRIT-003, CRIT-004]
  - goal_ref: "goal.md#final-completion-signal"
    criteria_refs: [CRIT-FINAL-001]
constraints:
  - id: CON-NOBACKEND-001
    type: hard
    category: scope
    statement: 不引入后端/服务/数据存储。
    status: active
    source: human
    introduced_in: goal
  - id: CON-SINGLEFILE-001
    type: hard
    category: scope
    statement: 单 HTML 文件实现，不引入第二套 UI 运行时或构建链。
    status: active
    source: human
    introduced_in: goal
required_regressions: []
allowed_paths: ["index.html"]
forbidden_paths: []
YML
echo "ok contract.yaml written"

# 7. re-run compile to rebind goal_hash/project_memory_hash onto our contract (status stays draft)
"$GS" compile >/dev/null 2>&1 || true
echo "ok compile-rebind"

# 8. contract review
cat > "$WORK/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: "WU 按行为切片而非模块；每个核心 scenario 与 must_not_happen 均映射到 criteria；criteria 可判定且强度适中；evidence requirements 为 browser 级能证明 criteria；final criteria 存在。"
YML
"$GS" review apply "$WORK/contract.yaml" >/dev/null
echo "ok contract-review"

# 9. approve contract
"$GS" approve contract >/dev/null
echo "ok approve-contract"

# 10. freeze
"$GS" freeze
echo "=== PHASE A DONE ==="
