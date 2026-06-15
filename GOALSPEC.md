# Goalspec v1 重构方案

## 1. Summary

废弃 Codespec，不做迁移、不保留兼容层，在 `../.goalspec` 新建一个项目自包含的 goal-driven spec 框架。

Goalspec 用 `bash + yq + git` 实现，安装到项目根目录后以 `.goalspec/` 管理长期项目记忆、当前 active goal、criteria、evidence、guardian verdict 和 history。

核心规则：

- `criteria` 是判断 goal 是否完成的唯一判据。
- executor 只产出代码、trace 和 evidence，不能自评完成。
- guardian 必须在 fresh context 中依据 contract/evidence/trace 输出 verdict。
- `complete` 是唯一完成入口。
- 实现方案不作为默认强制文档；Claude/Codex 在 contract 边界内自主决定具体实现路径。

## 2. Key Design Decisions

- 不兼容 Codespec：不读取 `spec.md`、`design.md`、`testing.md`、`meta.yaml`，不迁移 `REQ/ACC/VO/TC/RUN`，只继承其中有效思想。
- 项目必须是 git repo；`.goalspec/` 复制到项目根目录，框架和项目状态自包含。
- 不写默认 `design.md`，不维护详细实现方案；实现细节由 Claude/Codex executor 在 contract 约束下决定。
- `goal.md` 可以写得很细，必须完整承接人类意图，但只写目标、叙事、成功模型、边界、约束、风险盲区和 reopen triggers。
- `contract.yaml` 是编译产物，包含正式 criteria、work units、scope、constraints、evidence requirements；frozen 后 executor 不得修改。
- Work unit 是从 active goal 编译出的行为切片，用于小步执行和小步判定；不是模块任务，也不是最终 goal。
- `freeze` 前业务代码必须 clean；`complete` 前不强制 clean，但所有业务 diff 必须归属到已 pass 的 work unit。
- v1 不做自动多 agent runner、UI、并行 work units、自动 commit/push、危险命令自动执行。

## 3. Positioning

Goalspec 是项目开发 spec 框架，不是任务管理器、测试框架或自动 agent 平台。

它的职责是：

```text
承接人类目标
-> 编译 criteria / work units / constraints / evidence requirements
-> 约束 executor
-> 记录 trace 和 evidence
-> 让 guardian 独立判定
-> 沉淀长期项目记忆
```

## 4. Directory Model

安装后，项目根目录包含：

```text
.goalspec/
  goalspec
  runtime/
  ai/
  project/
  active/
  history/
  artifacts/
```

`project/` 保存长期项目记忆：

```text
profile.yaml            # 项目语言、默认命令、工具信息
memory.yaml             # capabilities / decisions
constraints.yaml        # 长期 hard/soft/environment constraints
regression-suite.yaml   # 长期 locked regressions
versions.yaml           # 完成历史索引
```

`active/` 保存当前 goal loop：

```text
goal.md                 # 人类意图权威
state.yaml              # 状态机、hash、approval、当前 WU、预算
contract.yaml           # draft/frozen contract，正式 criteria 在这里
reviews.yaml            # intake/contract/criteria/final review
questions.yaml          # blocking/nonblocking questions
trace.yaml              # executor 运行轨迹
evidence.yaml           # executor 产出的可复核事实
verdict.yaml            # guardian 独立判定
regressions.yaml        # 当前失败沉淀
memory-patch.yaml       # guardian 提议的长期记忆更新
```

## 5. Public Commands

命令入口：

```bash
.goalspec/goalspec
```

v1 命令集：

```bash
goalspec init
goalspec status
goalspec new-goal
goalspec review prompt|apply
goalspec compile
goalspec approve
goalspec freeze
goalspec next
goalspec evidence template|check
goalspec judge prompt|apply
goalspec scope-check
goalspec complete
goalspec reopen
goalspec version
```

命令职责：

- `init`：初始化项目自包含 `.goalspec/`，要求当前目录是 git repo。
- `status`：输出当前状态、下一步动作、角色、应读文件、允许/禁止修改文件、blocker、stale 信息。
- `new-goal`：创建新的 active goal；已有未完成 active goal 时阻断。
- `review prompt|apply`：生成 fresh context review prompt，并应用 review 输出。
- `compile`：从 `goal.md + project memory + constraints + regression-suite` 生成 draft contract。
- `approve`：记录 human approval，绑定 target hash。
- `freeze`：固化 reviewed draft contract，写入 contract hash，状态变为 `compiled`。
- `next`：选择下一个 work unit，生成 executor task。
- `evidence template|check`：生成或校验 evidence。
- `judge prompt|apply`：生成 guardian prompt，并应用 guardian verdict。
- `scope-check`：基于 git diff 检查文件修改是否在 WU 授权范围内。
- `complete`：唯一完成入口，验证所有 required criteria/verdict/scope/memory 条件。
- `reopen`：使旧 contract/evidence/verdict stale，回到目标或 contract 修正流程。

## 6. State Machine

`active/state.yaml` 是控制中心：

```yaml
active_goal_id: GOAL-20260615-001
status: draft
contract_hash: null
current_work_unit: null
iteration: 0
max_iterations: 6
max_failures_per_work_unit: 2
blocked_reason: null
reopen_reason: null
approvals: []
git:
  base_revision: null
  current_revision: null
```

正常状态流：

```text
draft
-> intake_reviewed
-> contract_draft
-> contract_reviewed
-> compiled
-> running
-> completed
```

异常状态：

```text
blocked
reopen_required
```

禁止跳转：

- `draft` 不能直接 `running`。
- `contract_draft` 不能直接 `completed`。
- `running` 不能直接 `completed`，必须经过 guardian verdict 和 `complete` 校验。
- `reopen_required` 不能继续执行旧 contract。

## 7. Goal Model

`active/goal.md` 是人类意图权威。它可以长，但只能长在目标语义上，不能混入实现方案。

模板结构：

```markdown
# Goal

## 1. Intent
完整说明本次目标，不限一两句话。

## 2. Narrative
连续描述真实运行流程、用户旅程、系统状态、产物、失败路径。

## 3. Success Model
- user_visible_success:
- system_observable_success:
- must_not_happen:
- minimum_acceptable_result:
- final_completion_signal:

## 4. Scope
- in_scope:
- out_of_scope:

## 5. Risk Scan
- scope-boundary:
- actor-permission:
- data-lifecycle:
- failure-degradation:
- non-functional-baseline:
- integration-boundary:

## 6. Goal Constraints
当前 goal 特有约束。

## 7. Sources and Decisions
- sources:
- confirmed_decisions:
- assumptions:

## 8. Open Questions
仍未解决的问题及影响。

## 9. Reopen Triggers
什么情况说明目标或 criteria 本身需要重开。
```

原则：

- `goal.md` 按人类场景、业务能力和成功画面组织，不按模块组织。
- `goal.md` 不写默认实现方案，不指定函数、类、service、表结构或施工步骤。
- 如果某个实现方向已经是长期项目决策，应写入 `project/memory.yaml` 或 `project/constraints.yaml`，而不是写成普通 goal 内容。

## 8. Criteria Model

Criteria 主要且正式地写在 `active/contract.yaml`。

原则：

- criteria 是 goal 是否完成的唯一判据。
- criteria 必须可判定、强度适中、覆盖 goal 的必要语义。
- criteria 不能由 executor 修改。
- criteria 错误、缺失、过弱、过强或模糊时，只能 reopen 后重新 compile/freeze。

正式 criteria 示例：

```yaml
criteria:
  - id: CRIT-LOGIN-001
    kind: machine
    priority: P0
    required_for_completion: true
    source_goal_refs:
      - goal.md#success-model
      - goal.md#scenario-password-login
    work_unit_refs:
      - WU-LOGIN-001
    statement: 正确邮箱密码登录后创建有效 session。
    event: POST /api/login
    pass_signals:
      - response.status == 200
      - response.headers["Set-Cookie"] contains "session_id"
      - GET /api/me with cookie returns current user id
    evidence_requirement_refs:
      - EVIDREQ-LOGIN-001
    status: active
```

Criteria 类型：

```text
machine
artifact
llm_judge
human
```

默认规则：

- 能 machine 判定就不用 `llm_judge`。
- 能 `llm_judge` 判定就不要伪装成人工确认。
- human criteria 必须说明为什么不能自动化。

Coverage map 是强制机制：

```yaml
coverage_map:
  - goal_ref: goal.md#scenario-success-login
    criteria_refs:
      - CRIT-LOGIN-001
  - goal_ref: goal.md#must-not-create-session-on-failure
    criteria_refs:
      - CRIT-LOGIN-FAIL-001
```

如果 goal 某部分不进入 criteria，必须写 coverage exception：

```yaml
coverage_exceptions:
  - goal_ref: goal.md#non-functional-baseline
    reason: 本 goal 不改变性能路径，沿用 CON-PERF-001，非本次 required criteria。
    approved_by: guardian
```

## 9. Work Unit Model

Work unit 是 executor 的最小执行单元，不是最终目标，也不是模块任务。

层级关系：

```text
active goal
  -> work unit goal
      -> criteria
      -> evidence requirements
```

Work unit 必须满足：

- 有局部行为目标。
- 有绑定 criteria。
- 有 allowed paths / forbidden paths。
- 有 required evidence。
- 能被 guardian 单独判定 `pass/fail/insufficient/reopen_required`。

错误示例：

```text
WU-001 创建 users.disabled 字段
WU-002 修改 AuthService
```

正确示例：

```text
WU-001 管理员禁用用户后，用户状态可持久查询
WU-002 禁用用户无法登录且无 session
WU-003 禁用用户已有 session 失效
WU-004 final integration 验证完整路径
```

Contract 示例：

```yaml
work_units:
  - id: WU-DISABLED-LOGIN-001
    goal: 禁用用户不能通过密码登录获得 session。
    depends_on:
      - WU-DISABLE-USER-001
    criteria_refs:
      - CRIT-DISABLED-LOGIN-001
      - CRIT-NO-SESSION-001
    evidence_requirement_refs:
      - EVIDREQ-DISABLED-LOGIN-001
    allowed_paths:
      - src/auth/**
      - tests/auth/**
    forbidden_paths:
      - src/billing/**
      - .goalspec/project/**
      - .goalspec/active/contract.yaml
      - .goalspec/active/verdict.yaml
```

每个 active goal 必须有 final criteria，用于整体集成收口。

## 10. Contract Model

`active/contract.yaml` 是编译产物。

流程：

```text
goal.md + project memory + constraints + regressions
-> compile
-> contract draft
-> contract / criteria review
-> approve contract
-> freeze
-> frozen contract
```

Contract 必须包含：

- `work_units`
- `criteria`
- `evidence_requirements`
- `coverage_map`
- `constraints`
- `required_regressions`
- `allowed_paths` / `forbidden_paths`
- `goal_hash`
- `project_memory_hash`
- `contract_hash` when frozen

`contract.yaml` 使用 `status: draft | frozen`。Draft 阶段可由 compiler agent 写；frozen 后只读。

`freeze` 前必须满足：

- intake review pass。
- goal approval 存在且 hash 有效。
- contract / criteria review pass。
- contract approval 存在且 hash 有效。
- 无 blocking questions。
- 业务代码 worktree clean。

## 11. Constraint Model

约束分三层：

```text
project constraints      # 长期约束
goal constraints         # 当前 goal 约束
compile-discovered       # compile 时发现的执行约束
```

约束类型：

```text
hard
soft
environment
decision preference
```

约束状态：

```text
candidate -> confirmed -> active
candidate -> rejected
active -> deprecated
```

进入 contract 的约束必须满足：

- project constraints: `active`
- goal constraints: `confirmed`
- compile-discovered constraints: `confirmed`

Unknown 不能假装 active。

示例：

```yaml
constraints:
  - id: CON-SEC-001
    type: hard
    category: security
    statement: 新增 API 必须验证当前用户权限。
    applies_to: backend_api
    status: active
    source: human
    introduced_in: bootstrap
```

约束发现时机：

- `init`：填写一开始就知道的长期约束。
- `intake`：当前 goal 讨论中浮现的目标约束。
- `compile`：准备执行时才能确定的 scope、provider、runtime、migration、regression 等执行约束。

Blocking unknown 阻断 freeze；execution unknown 会使相关 work unit blocked；nonblocking unknown 记录为 risk。

## 12. Review Mechanism

Goalspec 至少有三类 pre-execution review：

```text
intake review       # goal 是否接住人类意图
contract review     # contract 是否忠实且可执行
criteria review     # criteria 是否完整、可判定、适中
```

Review 必须由 fresh context guardian 执行，结果写入 `active/reviews.yaml`。

Intake review 检查：

- `goal.md` 是否冷启动自足。
- Intent 是否说明谁、场景、目标变化。
- Narrative 是否覆盖正常流程、失败路径、状态变化、产物。
- Success Model 是否有用户可见成功和系统可观察成功。
- `must_not_happen` 是否写清。
- Scope 是否有 in/out。
- Risk Scan 六类是否有结论或 blocking question。
- Open Questions 是否都标明影响。
- 是否存在两个合理解释会导致不同实现。

Contract / criteria review 检查：

- goal 的每个核心 scenario 是否覆盖到 criteria。
- `must_not_happen` 是否变成 negative criteria。
- `out_of_scope` 是否进入 hard constraints。
- work units 是否按行为拆，而不是模块拆。
- criteria 是否太弱、太强、模糊或不可终止。
- evidence requirements 是否能证明 criteria。
- constraints 和 regressions 是否正确注入。
- 是否有 blocking compile question。

## 13. Role Model

Goalspec v1 固定四个角色。

### intake agent

职责：

- 和人类讨论目标。
- 写 `active/goal.md`。
- 标出 open questions。
- 标出 goal constraints。
- 不写 contract。
- 不写代码。

允许写：

```text
active/goal.md
active/questions.yaml
```

### compiler agent

职责：

- 读 `goal.md + project memory`。
- 生成 `contract.yaml status: draft`。
- 生成 coverage map。
- 生成 compile questions。
- 不写代码。
- 不生成 final verdict。

允许写：

```text
active/contract.yaml when status=draft
active/questions.yaml
```

### executor agent

职责：

- 只处理 `goalspec next` 指定的 work unit。
- 在 allowed paths 内改代码。
- 运行验证命令。
- 记录 trace/evidence。
- 不判断完成。
- 不改 criteria。

允许写：

```text
业务代码 allowed_paths
active/trace.yaml
active/evidence.yaml
.goalspec/artifacts/**
```

禁止写：

```text
active/contract.yaml
active/verdict.yaml
active/goal.md during running
project/**
history/**
```

### guardian agent

职责：

- fresh context。
- 不读 executor 对话。
- 只读 contract/evidence/trace/artifacts。
- 判定 criteria。
- 输出 verdict。
- 提议 regression。
- 提议 memory patch。

允许写：

```text
active/reviews.yaml
active/verdict.yaml
active/regressions.yaml
active/memory-patch.yaml
```

禁止写：

```text
业务代码
active/contract.yaml
project/**
```

## 14. AI Instruction Model

根目录 `AGENTS.md` / `CLAUDE.md` 只保留短入口：

```text
本项目使用 Goalspec。
开始任务前运行或读取 .goalspec/goalspec status。
按 NEXT_ACTION 加载对应角色指令。
不要自评完成。
完成判定只能来自 guardian verdict 和 goalspec complete。
```

角色指令放在：

```text
.goalspec/ai/core.md
.goalspec/ai/intake.md
.goalspec/ai/compiler.md
.goalspec/ai/executor.md
.goalspec/ai/guardian.md
```

`goalspec status` 必须输出：

```text
STATE
NEXT_ACTION
ROLE
READ
MAY_EDIT
MUST_NOT_EDIT
BLOCKERS
CURRENT_WORK_UNIT
COMPLETION_CONDITION
```

`goalspec status --json` 供脚本和 AI 工具读取。

## 15. Evidence Model

Evidence 只记录事实，不记录结论。

原则：

```text
evidence != verdict
evidence != summary
evidence != self-evaluation
```

示例：

```yaml
evidence:
  - id: EV-001
    contract_hash: sha256:abc
    work_unit_ref: WU-001
    criteria_refs:
      - CRIT-001
    evidence_requirement_refs:
      - EVIDREQ-001
    command: pytest tests/auth/test_login.py::test_success -q
    exit_code: 0
    artifact_paths:
      - .goalspec/artifacts/EV-001-pytest.txt
    provider_source: not_required
    runtime_boundary: api
    persistence: postgres
    completion_level: db_persistent
    reproducible: true
    produced_by: executor
    produced_at: 2026-06-15T12:00:00Z
    residual_risk:
      level: none
      notes: none
```

Evidence facets：

```text
provider_source: not_required | fixture | fake | real_provider
runtime_boundary: none | function | api | worker | browser | deployment
persistence: none | memory | file | sqlite | postgres | external
completion_level: fixture_contract | in_memory_domain | api_connected | db_persistent | integrated_runtime | owner_verified
```

这些维度不能互相替代。

## 16. Trace and Regression Model

Trace 记录 executor 过程，不参与 pass 判定。

示例：

```yaml
traces:
  - id: TRACE-001
    contract_hash: sha256:abc
    work_unit_ref: WU-001
    iteration: 1
    role: executor
    started_at: ...
    ended_at: ...
    commands:
      - command: pytest tests/auth/test_login.py -q
        exit_code: 1
        artifact_path: .goalspec/artifacts/TRACE-001-pytest.txt
    changed_files:
      - src/auth/login.py
      - tests/auth/test_login.py
    summary: 实现登录成功路径，但错误密码测试仍失败。
    blockers: []
```

Regression 用于把真实失败沉淀为长期防回归资产。

示例：

```yaml
regressions:
  - id: REG-001
    source_trace: TRACE-001
    source_verdict: VER-001
    source_criteria: CRIT-002
    description: 错误密码时 API 返回 200 并创建 session。
    replay_command: pytest tests/auth/test_login.py::test_wrong_password_no_session -q
    expected_result: exit_code == 0
    status: proposed
```

Locked regressions 在后续 compile 触碰相关能力时自动注入 required evidence。

## 17. Verdict Model

Guardian verdict 枚举：

```text
pass
fail
insufficient
blocked
stale
reopen_required
```

示例：

```yaml
verdicts:
  - id: VER-001
    work_unit_ref: WU-001
    criteria_ref: CRIT-001
    evidence_refs:
      - EV-001
    contract_hash: sha256:abc
    evidence_hash: sha256:def
    verdict: pass
    reason: EV-001 的 API 测试返回 200 且 Set-Cookie 包含 session_id，满足 CRIT-001。
    next_action: none
    judged_by: guardian
    context: fresh
    judged_at: ...
```

规则：

- `pass`：criteria 被 evidence 证明。
- `fail`：代码或行为不满足 criteria，但 contract 没问题。
- `insufficient`：证据不足。
- `blocked`：外部条件缺失。
- `stale`：hash 不匹配或旧证据不可用于当前 contract。
- `reopen_required`：goal、criteria、scope 或 constraints 本身有问题。

`complete` 只接受 required criteria 最新 verdict 全部 `pass`。

## 18. Guardian Mechanism

Guardian 的目标：

```text
在干净上下文中，独立判断当前 evidence 是否满足 contract 中的 criteria，并把失败原因转成下一轮 executor 的明确反馈。
```

v1 使用文件协议：

```bash
goalspec judge prompt WU-002
goalspec judge apply /path/to/verdict.yaml
```

Guardian 输入：

- `active/contract.yaml`
- `active/evidence.yaml`
- `active/trace.yaml`
- `active/state.yaml`
- contract 引用的 project constraints
- artifacts

Guardian 不读 executor 对话，不修改代码，不修改 contract，不直接写 project memory。

## 19. Approval Model

Human approval 只用于关键语义和风险确认，不替代 criteria pass。

支持：

```bash
goalspec approve goal
goalspec approve contract
goalspec approve memory-patch
goalspec approve high-risk <id>
goalspec approve regression-waiver <id>
```

Approval 记录在 `state.yaml`，并绑定 target hash。

需要 approval 的事项：

- goal confirmation
- contract freeze
- memory patch
- high-risk action
- scope expansion
- regression waiver

Human approval 不能把 fail 的 criteria 批准成 pass。

## 20. Scope and Git Model

Git 是硬前提。

规则：

- `init` 要求当前目录是 git repo。
- `freeze` 前业务代码必须 clean。
- `complete` 前不强制 clean，但所有业务 changed files 必须归属到 passed WU。
- `scope-check` 基于 git diff 检查 changed files。
- history 记录 base revision、completed revision、changed files、dirty 状态。

Scope 分三层：

```text
project scope defaults
goal scope
work unit scope
```

`scope-check` 必须阻断：

- 修改 forbidden paths。
- 修改未授权业务文件。
- executor 修改 `project/**`、`history/**`、frozen contract、verdict。
- allowed paths 过宽且无 approval。

如果不强制每 WU commit，则通过 trace/verdict 记录 changed files 归属：

- executor trace 记录 `changed_files`。
- guardian pass verdict 可记录 `changed_files_accepted`。
- complete 检查所有 changed files 都属于某个 passed WU。

## 21. Complete Mechanism

`goalspec complete` 是唯一完成入口。

前置条件：

- `contract.status = frozen`
- 当前 contract hash 有效
- 所有 required criteria 最新 verdict = `pass`
- 所有 final criteria 最新 verdict = `pass`
- 所有 hard constraints verdict = `pass`
- 无 verdict = `fail/insufficient/blocked/stale/reopen_required`
- 无 blocking open questions
- `scope-check` pass
- required regressions pass
- `memory-patch.yaml` 存在并经 human approval
- 所有业务 changed files 均归属到 passed WU

通过后：

- 应用 `memory-patch.yaml` 到 project memory / constraints / regression-suite。
- 写 `project/versions.yaml`。
- 创建 `history/vNNNN/`。
- 复制 active 文件和 artifacts。
- `state.status = completed`。

`complete` 不自动 commit，不自动 push。

## 22. History and Long-Term Memory

每次 complete 创建：

```text
history/v0001/
  goal.md
  contract.yaml
  evidence.yaml
  verdict.yaml
  trace.yaml
  regressions.yaml
  memory-patch.yaml
  summary.yaml
```

`summary.yaml` 示例：

```yaml
version: v0001
goal_id: GOAL-20260615-001
completed_at: ...
contract_hash: ...
criteria_passed:
  - CRIT-001
capabilities_added:
  - CAP-LOGIN-001
regressions_added:
  - REG-LOGIN-001
changed_files:
  - src/auth/login.py
git:
  base_revision: ...
  completed_revision: ...
  dirty_at_completion: true
```

长期 memory 更新只能来自 guardian 生成、human approved 的 `memory-patch.yaml`。

## 23. Non-Goals for v1

v1 明确不做：

- Codespec 迁移。
- 自动多 agent runner。
- UI dashboard。
- 并行 work units。
- 自动 commit/push。
- 自动执行危险命令。
- 详细设计文档。
- 非 git 项目支持。
- 绑定 Claude/Codex API。

## 24. Implementation Notes

- 实现栈：`bash + yq + git`。
- 要求本机安装 `git` 和 `yq`。
- 不引入 Python/Node 运行时依赖。
- 避免单个巨大脚本，拆分为：

```text
runtime/lib/*.sh
runtime/commands/*.sh
runtime/templates/*
```

- v1 可以先用 shell/yq 做 schema 校验，后续再引入 JSON Schema。
- Hash v1 使用文件内容 sha256；所有 review/approval/verdict 绑定 target hash。

## 25. Test Plan

测试层级：

- 单元/脚本测试：command dispatch、state transition、hash/stale、schema required fields、verdict enum、approval hash。
- 集成 smoke：临时 git repo 中跑通 `init -> new-goal -> review -> compile -> approve -> freeze -> next -> evidence -> judge -> complete`。
- 负例测试：各类阻断条件必须 fail。
- Git 测试：非 git repo init fail；freeze 前业务 dirty fail；complete 可 dirty 但 diff 必须归属 passed WU。
- Regression 测试：guardian fail 可提出 regression；locked regression 后续注入 required evidence；waiver 必须 human approval。
- AI prompt 测试：`status` 和 `next` 输出必须包含角色、读写边界和下一步动作。

## 26. Mechanism Invariants

以下规则不是建议，而是 Goalspec v1 的硬机制；违反任一条，都应当被命令、review、judge 或 complete 阻断。

### 26.1 Authority Chain

- 人类意图权威只在 `active/goal.md`。
- 正式执行契约权威只在 `active/contract.yaml status=frozen`。
- 可复核事实权威只在 `active/evidence.yaml` 与 `active/trace.yaml`。
- 完成判定权威只在 `active/verdict.yaml` 与 `goalspec complete`。
- 长期项目事实权威只在 `project/memory.yaml`、`project/constraints.yaml`、`project/regression-suite.yaml`、`project/versions.yaml`。
- 聊天内容、commit message、普通测试输出、executor 自述都不是完成判据。

### 26.2 Role Separation

- intake agent 只承接目标语义，不写代码、不写 verdict。
- compiler agent 只生成 draft contract/questions，不写代码、不判完成。
- executor 只改业务代码和追加 trace/evidence，不得修改 frozen contract、verdict、project memory、history，不得自评完成。
- guardian 必须在 fresh context 中读取 contract/evidence/trace/artifact 判定，不写代码、不降级 criteria、不直接写长期 project memory。
- human approval 只确认关键语义、风险和长期记忆变更，不能把 fail 的 criteria 批准成 pass。

### 26.3 Freshness and Staleness

- `goal.md` 变化后，旧 intake review、goal approval、contract review、contract approval、frozen contract 全部 stale。
- `contract.yaml` 变化后，旧 evidence、旧 verdict、旧 complete 依据全部 stale。
- `evidence.yaml` 变化后，引用旧 evidence hash 的 verdict stale。
- `memory-patch.yaml` 变化后，旧 memory-patch approval stale。
- 任意 stale 状态都必须阻断 `next`、`judge apply` 或 `complete` 的继续推进，直到重新 review、approve、judge 或 freeze。

### 26.4 Work Unit Scheduling

- scheduler 一次只返回一个 WU。
- 若当前 WU 最新 verdict 为 `fail` 或 `insufficient`，`next` 必须继续返回同一 WU，而不是跳到后续 WU。
- 只有当前 WU 的 required criteria 全部 pass，且依赖满足时，才能进入下一个 WU。
- 所有 goal 必须有 final criteria；即使所有普通 WU 都 pass，没有 final criteria pass 也不能 complete。

### 26.5 Constraint and Question Discipline

- 约束必须区分 project constraints、goal constraints、compile-discovered constraints。
- 约束状态必须可区分 `candidate/confirmed/active/rejected/deprecated`。
- blocking question 未解决时，不能 freeze。
- execution unknown 不能伪装成 pass；必须显式转成 `blocked` 或 `reopen_required`。

### 26.6 Git and Scope Integrity

- git repo 是框架前提，不支持非 git 项目。
- `freeze` 前业务代码必须 clean，这是执行基线，不得放松。
- `complete` 前可 dirty，但所有业务 changed files 必须归属到 passed WU。
- `scope-check` 必须对 forbidden path、未归属文件、executor 越权修改、过宽的 allowed paths 生效。

## 27. Example Project: Web Snake

必须使用本框架完成一个示例项目，项目的要求只有一句话：

> 请设计一个网页版的贪吃蛇游戏(贪吃蛇项目目录为/home/admin/snake)，可以通过键盘上的方向键来控制运动

Goalspec 对这个输入的处理，不是直接进入编码，而是先把一句话编译成完整的 active goal、work units、criteria 和 evidence。

### 27.1 Example Goal

`active/goal.md` 应至少承接为如下语义：

- Intent：构建一个可在浏览器中游玩的单页贪吃蛇游戏，玩家通过键盘方向键控制蛇移动，游戏在页面加载后即可开始，不依赖账号、后端或联网服务。
- Narrative：
  - 玩家打开网页后看到游戏区域和当前分数。
  - 蛇按固定节奏自动移动。
  - 玩家按方向键可改变移动方向。
  - 蛇吃到食物后身体增长，分数增加，并刷新新的食物位置。
  - 蛇撞墙或撞到自己后，游戏结束，并给出可重新开始的反馈。
- Success Model：
  - user_visible_success：玩家可通过方向键实时控制蛇，能看到分数增长和游戏结束状态。
  - system_observable_success：浏览器运行时能接收键盘事件、更新蛇坐标、更新食物坐标、更新得分。
  - must_not_happen：蛇不能反向瞬间掉头导致自身重叠；食物不能刷新到蛇身体上；游戏结束后不能继续移动直到重开。
  - minimum_acceptable_result：只做桌面浏览器键盘控制，不包含触屏手势、联网排行榜、音效或皮肤系统。
  - final_completion_signal：在浏览器级验证中，正常移动、吃食物增长、撞墙结束、重新开始四条主路径全部通过。
- Scope：
  - in_scope：前端页面、游戏循环、键盘输入、分数显示、结束与重开。
  - out_of_scope：后端服务、用户系统、排行榜、移动端触控、多人模式、主题商城。
- Goal Constraints：
  - 不引入后端依赖。
  - 不引入实时联网能力。
  - 保持项目现有前端技术栈，不平行引入第二套 UI 运行时。

### 27.2 Example Work Units

编译后可以形成如下行为型 WU，而不是模块型任务：

- `WU-001`：页面加载后，游戏区域、初始蛇、初始食物和分数可见，蛇自动开始按固定节奏移动。
- `WU-002`：玩家按方向键可改变蛇的移动方向，且不能直接反向掉头。
- `WU-003`：蛇吃到食物后身体增长、分数增加，且新食物不会生成在蛇身体上。
- `WU-004`：蛇撞墙或撞到自己时游戏结束，结束后停止移动，并可通过明确操作重开。
- `WU-005`：最终浏览器级集成验证覆盖成功路径和失败路径。

### 27.3 Example Criteria

示例 required criteria：

- `CRIT-001`：页面首次加载后，游戏区域可见，蛇在无键盘输入情况下按固定 tick 连续移动。
- `CRIT-002`：按下方向键后，蛇在下一个有效 tick 按对应方向移动；若输入为与当前方向相反的方向，游戏逻辑忽略该输入。
- `CRIT-003`：蛇头进入食物坐标后，分数增加 1，蛇长度增加 1，新食物坐标不与蛇任一身体坐标重叠。
- `CRIT-004`：蛇撞墙或撞到自己时，游戏状态变为 game over，后续 tick 不再推进蛇位置。
- `CRIT-005`：玩家执行重开操作后，游戏重新初始化为初始状态，分数归零，蛇恢复初始长度和位置。
- `CRIT-FINAL-001`：在浏览器运行时，`CRIT-001` 到 `CRIT-005` 对应场景全部通过，且无 out_of_scope 功能被偷偷实现。

### 27.4 Example Evidence and Verdict

示例 evidence requirements：

- `EVIDREQ-001`：浏览器级自动化验证页面加载和自动移动，`runtime_boundary=browser`。
- `EVIDREQ-002`：浏览器级自动化验证方向键输入和非法反向输入保护。
- `EVIDREQ-003`：浏览器级自动化验证吃食物增长和食物刷新不重叠。
- `EVIDREQ-004`：浏览器级自动化验证撞墙/撞自身 game over。
- `EVIDREQ-005`：浏览器级自动化验证重开逻辑。

示例 guardian 判断：

- executor 即使声称“游戏已经能玩了”，如果只提供 unit test 或本地手动描述，没有 browser runtime evidence，verdict 也必须是 `insufficient`。
- 如果实现了排行榜弹窗、音效商店之类 out_of_scope 内容，即使核心游戏能玩，scope-check 和 final criteria 也应阻断 complete。
- 如果 `CRIT-002` 忘了覆盖反向掉头保护，contract review 就应判 criteria coverage 不完整，freeze 不能通过。

### 27.5 Example Acceptance Value

这个示例项目用于验收 Goalspec 方案时，应证明三件事：

- 一句非常短的人类输入，确实能被 Goalspec 承接成完整而不含实现方案的 `goal.md`。
- 编译出的 WU 是行为切片，而不是“写某个模块/某个函数”的施工清单。
- 完成依赖正式 criteria、browser evidence、guardian verdict 和 complete gate，而不是“游戏看起来能玩了”的主观判断。

## 28. Assumptions

- v1 依赖 `git` 和 `yq`。
- v1 不自动调用 Claude/Codex API；fresh context guardian 通过 prompt/apply 文件协议完成。
- v1 不自动 commit/push；history 记录 git revision、dirty state、changed files。
- v1 不支持 Codespec 迁移。
- v1 默认串行执行 work units。

