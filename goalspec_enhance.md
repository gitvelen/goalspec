# Goalspec Goal-Driven 优化方案

> **状态（2026-06）：已落地。** 引擎已按本方案移除 work units / `/goalspec next` / `CURRENT_WORK_UNIT`（§2/§3/§13），执行模型已折叠为 Master/Subagent 两角色（§2/§9/§12），生命周期已迁移到 §4 状态名。本文件保留为历史设计与符合性依据；以代码与 `docs/adr/` 为现行权威。

## 1. 目标

## 1. 目标

Goalspec 应该是一个 Goal-Driven AI 执行框架，而不是任务调度器。

框架需要帮助 Claude、Codex、Lingma 等 AI 工具稳定完成四件事：

1. 在明确的 intake 窗口内承接用户真实意图。
2. 将用户意图转化为清晰的 Goal、Criteria 和 Constraints。
3. 只有在人类显式确认后，才能冻结 Goal、Criteria 和 Constraints。
4. 只有在人类显式输入 `/goalspec run` 后，才能执行冻结后的 Goal-Driven Prompt。

核心不变量是：

```text
AI 工具不得执行“任务清单”。
AI 工具必须执行冻结后的 Goal-Driven Prompt。
```

Goal-Driven Prompt 包含最终 Goal、Criteria、Constraints，以及 Master Agent / Subagent 控制循环。Subagent 持续朝 Goal 工作；Master Agent 按 Criteria 评估结果，并在 Criteria 未满足时继续驱动 Subagent 工作，直到 Criteria 满足、用户停止流程，或出现必须由人类处理的阻塞性歧义。

## 2. 核心模型

公开模型只保留三个权威产物：

```text
Goal        用户的最终目标
Criteria    判断 Goal 是否达成的成功标准
Constraints AI 执行时不得违反的边界
```

执行模型只保留两个 agent 角色：

```text
Master Agent   控制流程，并判断 Criteria 是否满足
Subagent       在 Constraints 下持续朝 Goal 工作
```

新框架中应移除 `work unit`、`WU-*`、`/goalspec next` 和 `CURRENT_WORK_UNIT`。这些概念会把系统拉回 task-driven，增加用户和 AI 的理解摩擦。

如果实现层需要内部范围控制、证据归因或重试记录，可以使用内部概念，例如 `attempt` 或 `execution_scope`。这些概念不得成为用户可见目标，也不得作为 Master Prompt 中的执行目标。

## 3. 用户命令面

用户命令应保持最小化：

```text
/goalspec start <intent>
/goalspec source <path>
/goalspec end
/goalspec run
/goalspec status
/goalspec reopen <reason>
```

自然语言确认也是一等交互：

```text
确认
修改为...
不同意，第 C2 条改成...
```

`compile`、`approve`、`freeze`、`review`、`judge`、`evidence`、`complete` 等可以作为内部命令存在，但不应作为普通用户命令教学。`/goalspec next` 不应存在于新的用户命令面中。

## 4. 生命周期

生命周期如下：

```text
no_goal
  -> intake_collecting
  -> spec_drafting
  -> awaiting_human_confirmation
  -> frozen_ready
  -> prompt_ready
  -> running
  -> judging_or_continuing
  -> completed
```

### `/goalspec start`

`/goalspec start <intent>` 开启正式意图窗口。

窗口开启期间，AI 工具可以：

- 记录用户对话。
- 追问澄清问题。
- 按用户要求添加 source 材料。
- 跟踪看起来像 Constraints 或不确定项的内容。

窗口开启期间，AI 工具不得：

- 冻结 Goal、Criteria 或 Constraints。
- 生成 Goal-Driven Prompt。
- 修改业务代码。
- 开始实施。
- 自行判断 intake 已结束。

### `/goalspec source`

`/goalspec source <path>` 将文件或目录加入当前 intake 窗口。

source 材料不会关闭 intake。即使 source 看起来已经很完整，只要用户没有显式输入 `/goalspec end`，AI 工具都必须继续收集，不得擅自停止。

### `/goalspec end`

`/goalspec end` 关闭正式意图窗口。

只有收到该命令后，AI 工具才能分析 start/end 之间的完整对话和所有 source 材料，并起草：

- Goal
- Criteria
- Constraints
- Out of Scope
- Blocking Questions

随后 AI 必须把这些产物展示给用户，请用户确认或修改。

### 人类确认

用户确认会冻结 Goal、Criteria 和 Constraints。

确认表示：

```text
这些 Goal、Criteria 和 Constraints 是正确的。
```

确认不表示：

```text
开始实施。
```

确认后，Goalspec 应生成 Goal-Driven Prompt，并进入 `prompt_ready`。AI 必须停止，并告知用户：只有收到 `/goalspec run` 后才会开始实施。

### `/goalspec run`

`/goalspec run` 是唯一实施入口。

当用户输入 `/goalspec run` 时，AI 工具必须：

1. 运行 Goalspec 的 run 命令。
2. 验证 Goal、Criteria 和 Constraints 已冻结。
3. 验证 Goal-Driven Prompt 存在且未 stale。
4. 完整读取 Goal-Driven Prompt。
5. 将该 Prompt 作为当前执行的控制指令。
6. 执行 Prompt 中定义的 Master Agent / Subagent 循环。

如果任何前置条件缺失，`/goalspec run` 必须拒绝执行，并说明需要用户审阅或确认的事项。

## 5. 人类门禁

以下情况必须询问人类：

- `/goalspec end` 后已经生成 Goal、Criteria 和 Constraints 草案。
- 用户意图存在会改变实现方向的歧义。
- 某条 Criterion 会改变“什么算完成”的判断。
- 某条 Constraint 会影响安全、权限、数据、兼容性、成本、外部服务、迁移或部署。
- source 材料与会话意图冲突。
- scope 或 out-of-scope 不清，会导致 AI 多做或少做。
- AI 推导出用户没有明确表达、但会影响完成判定的成功条件。
- 执行中发现 Goal、Criteria 或 Constraints 本身错误或不足。

AI 不应向用户询问普通实现细节，除非这些细节会改变 Goal、Criteria、Constraints、风险边界或用户可见行为。

## 6. Criteria 设计

Criteria 是框架中最难的部分。它必须完整覆盖用户意图，同时清晰到 Master Agent 可以独立判断 pass/fail。

最终 Criteria 应保持简单：

```yaml
criteria:
  - id: C1
    statement: "用户在 X 场景下能够完成 Y，并看到 Z 结果。"

  - id: C2
    statement: "当 A 条件不满足时，系统不得发生 B，并应给出 C 反馈。"

optional_criteria:
  - id: O1
    statement: "系统可以额外支持 D，但不影响本次完成判定。"
```

### Criteria 生成 checklist

AI 工具在起草 Criteria 时，必须按资深测试专家的视角进行内部检查：

```text
正常路径：用户最核心的成功路径是什么？
变体路径：角色、输入、状态或上下文差异是否影响目标？
负向路径：哪些事情必须不能发生？
边界条件：空值、重复、最小值、最大值或异常状态是否影响目标？
权限与安全：谁可以做，谁不能做？
数据生命周期：哪些数据应被创建、更新、持久化、回滚或清理？
集成边界：API、数据库、文件、浏览器行为或外部服务是否影响完成？
失败降级：失败时用户应看到什么，系统应保持什么状态？
非功能底线：性能、兼容性、可靠性或可用性是否直接属于成功条件？
非目标：哪些内容不应被拉入本次 Goal？
```

该 checklist 是 AI 起草 Criteria 时的内部纪律，不是最终 schema。最终 Criteria 应保持简洁、清晰、易读。

### Criteria lint 规则

每条 Criterion 必须通过四项检查：

```text
Clear
  避免“合理、良好、优化、完整、正确、充分支持”等模糊词，
  除非这些词已被具体定义。

Decidable
  Master Agent 可以基于 evidence 判断 pass/fail。

Goal-relevant
  如果该 Criterion 失败，用户会合理地认为 Goal 没有达成。

Minimal
  不包含实现步骤、技术选型、内部任务清单或镀金需求。
```

如果某条 Criterion 需要额外解释才能判断，它就还不够清晰。

如果某条 Criterion 看起来很专业，但失败后并不影响用户 Goal，就应删除或移入 `optional_criteria`。

### 人类审阅呈现方式

冻结前，AI 工具应使用自然语言向用户展示：

```text
我理解你的目标是：
...

我认为完成必须满足：
C1 ...
C2 ...
C3 ...

我认为明确不做：
...

我还不确定的问题是：
...
```

框架不应依赖 `source_refs` 这类形式化字段来自证“分析到了”。真正重要的是：用户能轻松看出 AI 是否理解了自己的意图。

## 7. Constraints 设计

Constraints 是执行边界，不是成功标准。

示例：

- 不修改某个子系统。
- 不引入付费外部服务。
- 保持某个 API 的向后兼容。
- 不记录敏感用户数据。
- 将改动限制在某个部署边界或运行时边界内。

Constraints 应与 Goal 和 Criteria 一起冻结。执行期间，AI 工具不得修改 Constraints。若 AI 发现某条 Constraint 错误或阻碍 Goal 达成，必须停止并请求 reopen。

## 8. Goal-Driven Prompt 生成

只有满足以下条件后，才能生成 Goal-Driven Prompt：

```text
Goal 已冻结。
Criteria 已冻结。
Constraints 已冻结。
不存在 blocking questions。
用户已经确认冻结产物。
```

Prompt 生成不得开始实施。它只会让状态进入 `prompt_ready`。

生成的 Prompt 应存储为：

```text
.goalspec/active/goal-driven-prompt.md
```

Prompt 应绑定冻结产物的 hash：

```yaml
goal_hash:
criteria_hash:
constraints_hash:
prompt_hash:
generated_at:
confirmed_at:
```

如果 Goal、Criteria 或 Constraints 发生变化，Prompt 立即 stale，`/goalspec run` 必须拒绝执行。

## 9. Goal-Driven Prompt 内容

Prompt 应保留 Goal-Driven 的原始精神，只加入防止框架偏移所需的规则。

建议生成模板：

```text
# Goal-Driven(1 master agent + 1 subagent) System

Here we define a goal-driven multi-agent system for solving any problem.

Goal: [[[[[DEFINE YOUR GOAL HERE]]]]]

Criteria: [[[[[DEFINE YOUR CRITERIA HERE]]]]]

Constraints: [[[[[DEFINE YOUR Constraints HERE]]]]]

Here is the System: The system contains a master agent and a subagent. You are the master agent, and you need to create 1 subagent to help you complete the task.



## Subagent

The subagent's goal is to complete the task assigned by the master agent. The goal defined above is the final and the only goal for the subagent. The subagent should have the ability to break down the task into smaller sub-tasks, and assign the sub-tasks to itself or other subagents if necessary. The subagent should also have the ability to monitor the progress of each sub-task and update the master agent accordingly. The subagent should continue to work on the task until the criteria under Constraints are met.


## Master agent's description:

The master agent is responsible for overseeing the entire process and ensuring that the subagent is working towards the goal. The only 3 tasks that the main agent need to do are:

1. Create subagents to complete the task.
2. If the subagent finishes the task successfully or fails to complete the task, the master agent should evaluate the result by checking the criteria for success. If the criteria are met, the master agent should stop all subagents and end the process. If the criteria are not met, the master agent should ask the subagent to continue working on the task until the criteria are met.
3. The master agent should check the activities of each subagent for every 5 minutes, and if the subagent is inactive, please check if the current goal is reached and verify the status. If the goal is not reached, restart a new subagent with the same name to replace the inactive subagent. The new subagent should continue to work on the task and update the master agent accordingly.
4. This process should continue until the criteria for success are met. DO NOT STOP THE AGENTS UNTIL THE USER STOPS THEM MANUALLY FROM OUTSIDE.

## Basic design of the goal-driven double agent system in pseudocode:

create a subagent to complete the goal

while (criteria are not met) {
  check the activty of the subagent every 5 minutes
  if (the subagent is inactive or declares that it has reached the goal) {
    check if the current goal is reached and verify the status
    if (criteria are not met) {
      restart a new subagent with the same name to replace the inactive subagent
    }
    else {
      stop all subagents and end the process
    }
  }
}
```

该 Prompt 不应把 work units 表述为执行目标。

## 10. `/goalspec run` 执行契约

`/goalspec run` 必须强制 AI 工具执行生成的 Goal-Driven Prompt，而不是只打印 Prompt 后依赖 AI 自觉遵守。

用户输入 `/goalspec run` 后，AI adapter 必须：

1. 运行项目本地 run 命令。
2. 完整读取 run 输出。
3. 如果 run 输出指向 `.goalspec/active/goal-driven-prompt.md`，必须读取该文件全文。
4. 将该 Prompt 作为当前 turn 的最高优先级任务指令。
5. 如果 Prompt 缺失、stale 或未 frozen，拒绝修改业务代码。
6. 执行 Master Agent / Subagent 循环。

run 命令应输出明确的执行信封：

```text
GOALSPEC_RUN_ALLOWED: true
PROMPT_FILE: .goalspec/active/goal-driven-prompt.md
PROMPT_HASH: sha256:...
READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true

# Goal-Driven Prompt
...
```

如果不允许执行，应输出：

```text
GOALSPEC_RUN_ALLOWED: false
BLOCKER: <reason>
NEXT_USER_ACTION: <用户需要审阅或确认的事项>
```

AI adapter 必须将 `GOALSPEC_RUN_ALLOWED: false` 视为实施硬停止。

## 11. AI 工具 adapter 规则

`skills/goalspec/SKILL.md`、`AGENTS.md`、`CLAUDE.md` 和 Lingma 命令说明应包含硬规则：

```text
当用户输入 /goalspec run 时，必须执行生成的 Goal-Driven Prompt。
修改业务代码前，必须读取 .goalspec/active/goal-driven-prompt.md 全文。
必须将 Prompt 中的 Goal、Criteria 和 Constraints 视为权威。
不得用自己的实施计划替代该 Prompt。
不得凭记忆执行。
如果 Prompt 缺失、stale 或未 frozen，不得继续。
不得将“确认”视为 run 许可。
不得将“继续”视为 run 许可，除非用户明确输入 /goalspec run。
```

如果 AI 工具支持 subagents，`/goalspec run` 应创建且只创建一个 Subagent 执行。如果 AI 工具不支持 subagents，AI 必须模拟角色分离：

```text
Master Evaluation
Subagent Work
Evidence/Progress Report
Master Evaluation
继续或停止
```

## 12. Evidence 和 Verdict

Evidence 仍然有价值，但应绑定 Criteria 和 attempts，而不是 work units。

建议结构：

```yaml
evidence:
  - id: E1
    criteria: [C1, C2]
    attempt: A1
    command: "..."
    result: "..."
    artifacts: []
    produced_by: subagent
```

Verdict 是 Master Agent 或 Guardian 对 evidence 是否满足 Criteria 的判断：

```yaml
verdicts:
  - criteria: C1
    verdict: pass
    reason: "..."
    evaluated_by: master
```

Subagent 可以产出 evidence。Subagent 不能产出最终成功 verdict。

## 13. Scope 和 Attempts

Attempts 是内部执行记录，用于安全控制和可追踪性：

```yaml
attempts:
  - id: A1
    target_criteria: [C1]
    allowed_paths: []
    forbidden_paths: []
    status: running
```

Attempts 不得被呈现为 Goal。Master Prompt 应说明 Subagent 正在朝 Goal 和 Criteria 工作，而不是朝 attempt 工作。

scope-check 可以使用 attempts 判断变更文件是否在允许范围内。

## 14. Status 输出

`/goalspec status` 应面向用户，不应暴露 work units。

推荐字段：

```text
STATE:
GOAL:
FROZEN:
PROMPT_READY:
RUN_ALLOWED:
NEEDS_HUMAN_CONFIRMATION:
BLOCKERS:
UNMET_CRITERIA:
NEXT_USER_ACTION:
```

示例：

```text
STATE: intake_collecting
NEXT_USER_ACTION: 继续提供意图、添加 source，或运行 /goalspec end。
```

```text
STATE: awaiting_human_confirmation
NEXT_USER_ACTION: 审阅 Goal、Criteria、Constraints，并回复确认或修改意见。
```

```text
STATE: prompt_ready
RUN_ALLOWED: true
NEXT_USER_ACTION: 运行 /goalspec run 开始实施。
```

## 15. 需要实现或调整的文件

建议新增或重写：

```text
runtime/commands/start.sh
runtime/commands/source.sh
runtime/commands/end.sh
runtime/commands/run.sh
runtime/commands/status.sh
runtime/commands/reopen.sh
runtime/commands/prompt.sh
runtime/templates/active/goal.yaml
runtime/templates/active/criteria.yaml
runtime/templates/active/constraints.yaml
runtime/templates/active/goal-driven-prompt.md
runtime/templates/ai/core.md
runtime/templates/AGENTS.md
runtime/templates/CLAUDE.md
skills/goalspec/SKILL.md
skills/goalspec/references/command-map.md
README.md
```

新框架文档和用户流程中应移除：

```text
work_units
WU-*
/goalspec next
CURRENT_WORK_UNIT
```

## 16. 实施阶段

### Phase 1: 用户命令模型

- 添加用户命令 `start`、`source`、`end`、`run`、`status` 和 `reopen`。
- 从 help、README、skill 指令和 command map 中移除 `/goalspec next`。
- 确保 `start` 开启 intake 窗口，`end` 是唯一关闭窗口的动作。

### Phase 2: 冻结产物

- 将 active 产物拆分为 Goal、Criteria 和 Constraints。
- `criteria` 默认全部 required。
- 添加 `optional_criteria`。
- 添加 Goal、Criteria 和 Constraints 的 frozen 状态与 hash 绑定。
- 确保确认只冻结产物，不开始实施。

### Phase 3: Criteria 起草与审阅

- 更新 AI intake/spec 指令，加入资深测试专家 checklist。
- 添加 Criteria lint：Clear、Decidable、Goal-relevant、Minimal。
- 要求 AI 在 freeze 前展示自然语言确认视图。

### Phase 4: Goal-Driven Prompt

- 只有产物 frozen 后才生成 `.goalspec/active/goal-driven-prompt.md`。
- 将 Prompt 与冻结产物 hash 绑定。
- 如果任一冻结产物变化，Prompt stale。
- 生成 Prompt 不进入 running。

### Phase 5: run 强制执行

- 将 `/goalspec run` 实现为唯一实施网关。
- run 输出完整 Prompt，或输出强制读取 Prompt 的文件路径与 hash。
- AI adapter 必须将 missing/stale Prompt 视为硬停止。
- AI 工具必须执行 Master Agent / Subagent 循环。

### Phase 6: Evidence、Verdict 和 Completion

- Evidence 绑定 Criteria 和 attempts。
- Subagent 不能自证成功。
- Master Agent 或 Guardian verdict 评估 Criteria。
- 只有全部 required Criteria 在 Constraints 下 pass，completion 才能成功。

## 17. 验收标准

以下条件全部满足后，实施才算合格。

### 用户命令验收标准

- `/goalspec start <intent>` 会开启正式 intake 窗口。
- `/goalspec source <path>` 会把材料加入已开启的 intake 窗口。
- `/goalspec end` 是唯一能关闭 intake 窗口的命令。
- `/goalspec end` 前，AI 工具不得冻结 Goal、Criteria 或 Constraints。
- `/goalspec end` 前，AI 工具不得生成 Goal-Driven Prompt。
- `/goalspec end` 前，AI 工具不得修改业务代码。
- `/goalspec run` 是唯一能开始实施的用户命令。
- `确认` 只会冻结已批准产物，不会开始实施。
- `继续` 不会开始实施，除非用户明确包含 `/goalspec run`。
- `/goalspec next` 不作为用户命令出现在文档、help 或 AI adapter 流程中。

### Intake 验收标准

- start/end 之间的会话内容会作为一个正式意图窗口被捕获和分析。
- 窗口内添加的 source 材料会被纳入分析。
- AI 工具不会在没有 `/goalspec end` 的情况下自行结束 intake。
- `/goalspec end` 后，AI 工具会展示 Goal、Criteria、Constraints、out-of-scope 和 blocking questions。
- 如果 source 材料与会话意图冲突，AI 会要求人类解决冲突。
- 如果某个决策会改变 Goal、Criteria、Constraints 或 scope，AI 会询问人类。
- AI 不会询问普通实现细节，除非该细节影响 Goal、Criteria、Constraints 或风险边界。

### Criteria 验收标准

- Criteria 清晰、可判断、与 Goal 相关且最小化。
- Criteria 不使用“合理、良好、优化、正确、完整”等模糊词，除非已具体定义。
- Criteria 不编码实现步骤、内部任务清单或技术选型。
- `criteria` 下的所有条目默认视为 required。
- 框架不会要求或生成重复的 `required: true` 字段。
- 可选成功想法放入 `optional_criteria`，且不阻断 completion。
- AI 起草 Criteria 时会应用资深测试专家 checklist，覆盖正常路径、变体路径、负向路径、边界、权限、数据生命周期、集成边界、失败降级、非功能底线和非目标。
- 展示给用户的最终 Criteria 保持简洁、清晰、可读。
- 如果某条 Criterion 不能由 Master Agent 基于 evidence 判断 pass/fail，freeze 前必须拒绝或重写。
- 如果缺少某条 Criterion 会导致用户认为 Goal 未达成，AI 必须补充该 Criterion 或提出 blocking question。

### Freeze 验收标准

- Goal、Criteria 和 Constraints 只能在人类显式确认后 frozen。
- frozen 的 Goal、Criteria 和 Constraints 均有 hash 绑定。
- 修改任一 frozen 产物都会使依赖的 Prompt 和 approval stale。
- frozen confirmation 不会进入 running 状态。
- freeze 后系统进入 prompt-ready 准备阶段，而不是开始实施。

### Goal-Driven Prompt 验收标准

- Goal-Driven Prompt 只会在 Goal、Criteria 和 Constraints frozen 后生成。
- Prompt 包含 frozen Goal。
- Prompt 包含 frozen Criteria for success。
- Prompt 包含 frozen Constraints。
- Prompt 定义恰好 1 个 Master Agent 和 1 个 Subagent。
- Prompt 声明 Subagent 的唯一最终 Goal 是 frozen Goal。
- Prompt 声明内部任务不是成功标准。
- Prompt 声明 Subagent 不能宣布最终成功。
- Prompt 声明 Master Agent 必须严格按 Criteria 评估 progress。
- Prompt 声明 Criteria satisfaction 是唯一成功条件。
- Prompt 声明执行期间不得修改 Goal、Criteria 或 Constraints。
- Prompt 指示 Master Agent：如果 Goal、Criteria 或 Constraints 看起来错误，必须停止并请求 reopen。
- Prompt 不把 work units 表述为 goals。
- Prompt 与 frozen artifacts 通过 hash 绑定。
- 如果 Prompt stale，`/goalspec run` 会拒绝执行。

### Run 验收标准

- Goal 未 frozen 时，`/goalspec run` 拒绝执行。
- Criteria 未 frozen 时，`/goalspec run` 拒绝执行。
- Constraints 未 frozen 时，`/goalspec run` 拒绝执行。
- 存在 blocking questions 时，`/goalspec run` 拒绝执行。
- Goal-Driven Prompt 缺失时，`/goalspec run` 拒绝执行。
- Goal-Driven Prompt stale 时，`/goalspec run` 拒绝执行。
- 只有允许执行时，`/goalspec run` 才输出 `GOALSPEC_RUN_ALLOWED: true`。
- 不允许执行时，`/goalspec run` 输出 `GOALSPEC_RUN_ALLOWED: false` 和清晰 blocker。
- 允许执行时，run 命令输出 Prompt 文件路径和 Prompt hash。
- 允许执行时，run 命令输出完整 Goal-Driven Prompt，或强制 AI adapter 在行动前完整读取 Prompt。

### AI Adapter 验收标准

- 收到 `/goalspec run` 后，AI adapter 会在修改业务代码前完整读取 Goal-Driven Prompt。
- AI adapter 将 Prompt 视为当前执行的控制指令。
- AI adapter 不会用自己的任务计划替代 Prompt。
- AI adapter 不会凭记忆执行。
- 如果 Prompt 缺失、stale 或未 frozen，AI adapter 拒绝继续。
- 如果 AI 工具支持显式 subagents，AI adapter 创建且只创建一个 Subagent 执行。
- 如果 AI 工具不支持显式 subagents，AI adapter 通过可见的 Master evaluation 和 Subagent work 阶段模拟角色分离。
- Criteria 未满足时，AI adapter 会继续工作。
- AI adapter 不会因为测试通过、任务完成或 Subagent 声称完成而宣布成功。
- 如果执行中发现 Goal、Criteria 或 Constraints 错误或不足，AI adapter 会停止并请求人类输入。

### Evidence 和 Verdict 验收标准

- Evidence 绑定 Criteria，而不是 work units。
- Evidence 可以绑定内部 attempts 以便追踪。
- Evidence 记录事实、命令、结果和 artifacts。
- Subagent 可以产出 evidence，但不能产出最终成功 verdict。
- Master Agent 或 Guardian 评估 evidence 是否满足 Criteria。
- 只有相关 evidence 支持时，Criterion 才能 pass。
- 任一 required Criterion 缺少 pass verdict 时，completion 被阻断。
- 违反 Constraints 时，completion 被阻断。

### Scope 和安全验收标准

- `/goalspec run` 前不得修改业务代码。
- scope-check 使用内部 attempts 或 execution scopes，而不是用户可见 work units。
- Attempts 不会作为 goals 出现在用户可见 Prompt 中。
- 执行期间 forbidden paths 会被强制执行。
- 如果实施需要违反 Constraint，执行会停止并请求 reopen。

### 文档验收标准

- README 将 Goalspec 解释为 Goal-Driven Prompt 框架，而不是任务调度器。
- README 只记录最小用户命令。
- README 明确说明 `/goalspec run` 是唯一实施入口。
- README 明确说明确认会冻结产物，但不会开始实施。
- AI 工具说明包含执行生成的 Goal-Driven Prompt 的硬规则。
- 文档不会把 `/goalspec next` 作为用户流程教学。

### 回归验收标准

- 测试覆盖 start/end intake 门禁。
- 测试覆盖 `/goalspec run` 前不得实施。
- 测试覆盖 frozen artifact hash staleness。
- 测试覆盖只有 freeze 后才能生成 Prompt。
- 测试覆盖 stale Prompt 阻断 run。
- 测试覆盖 Criteria clarity lint。
- 测试覆盖 optional Criteria 不阻断 completion。
- 测试覆盖 Subagent self-completion 不被接受。
- 测试覆盖只有全部 required Criteria pass 后才能 completion。
