# Goalspec

Goalspec 是一个项目内的 Goal-Driven Prompt 框架，用于 AI 辅助开发。
它的目标是防止 AI 漂移成“任务清单执行器”：AI 只能执行冻结后的 Goal-Driven Prompt，而一次变更也只能通过项目内的 CLI 正式收口。

对外公开模型包含四类核心工件：

- `Goal` —— 用户真正想达成的结果。
- `Criteria` —— 由 `Master Agent` 用来判定是否完成的必需成功标准。
- `Constraints` —— AI 不可越过的边界。
- `Close Package` —— 所有必需 `Criteria` 通过后生成、供人工审阅的交付包。

## 三个核心动作

用户只需要理解三个动作：

```text
/goalspec start <intent>   开始定义一次变更
/goalspec run              开始实施与验收；当 Criteria 通过时生成 close package
/goalspec close            正式收口：应用记忆、归档、commit、push、创建 PR
```

决定一次变更是否真的完成，只有一条规则：

> 只有状态为 `closed`，才表示这次变更已经完整结束，下一次 `/goalspec start <intent>` 才能开始。

## 何时使用 Goalspec

Goalspec 默认是显式启用（opt-in）模式。

只有当人类明确做了下面这些事之一时，才进入 Goalspec 生命周期：

- 明确执行某个 `/goalspec ...` 命令；
- 明确要求开始一次正式的 Goalspec 变更；
- 明确要求本次变更按 Goalspec 流程执行。

不能因为仓库里存在 `.goalspec/`，就默认进入该生命周期。
普通问答、调试、小型一次性改动、探索性工作和闲聊，如果没有显式 opt-in，默认都在框架之外进行。

AI 工具可以建议对较大或高风险的变更使用 Goalspec，但不能悄悄把普通请求升级成 Goalspec 工作流。

## 安装

```bash
cd /path/to/project
git init                  # 如果项目还不是 git 仓库
/path/to/goalspec init
```

这会创建 `.goalspec/`，并把受管的 Goalspec 指导块写入 `AGENTS.md` 和 `CLAUDE.md`。
根目录指导块只保留薄路由和硬门禁摘要；详细角色规则在 `.goalspec/ai/core.md`。

可选的 AI 适配器安装：

```bash
/path/to/goalspec install-ai codex    # 或 claude / lingma
```

## 用户命令

只使用下面这些面向用户的命令：

```text
/goalspec start <intent>
/goalspec source <path>
/goalspec end
/goalspec run
/goalspec close
/goalspec status
/goalspec reopen <reason>
/goalspec scope amend --allow <glob> --reason <text>
```

`/goalspec run` 是唯一的实施入口。`/goalspec close` 是唯一的收口入口。
`继续` 只有在显式包含 `/goalspec run` 时才表示开始实施，只有在显式包含 `/goalspec close` 时才表示开始收口。

## 项目开发状态图

下面这张项目开发状态图，是一次 Goalspec 变更的权威生命周期图。
看这张图时，要同时关注主路径、人工审核门禁，以及两个恢复环路。

```text
                                   +----------------------+
                                   |       no_goal        |
                                   +----------+-----------+
                                              |
                                              | /goalspec start <intent>
                                              v
                                   +----------------------+
                                   |  intake_collecting   |
                                   +----------+-----------+
                                              |
                                              | /goalspec end
                                              v
                                   +----------------------+
                                   |    spec_drafting     |
                                   +----------+-----------+
                                              |
                                              | 草案可供审核
                                              v
                             +----------------+----------------+
                             | awaiting_human_confirmation     |
                             +----------------+----------------+
                                              |
                                              | freeze
                                              v
                                   +----------------------+
                                   |     ready_to_run     |
                                   +----------+-----------+
                                              |
                                              | /goalspec run
                                              v
                                   +----------------------+
                                   |       running        |
                                   +----------+-----------+
                                              |
                                              | 所有必需 Criteria 通过，
                                              | 且 /goalspec run 生成
                                              | close package
                                              v
                                   +----------------------+
                                   |   ready_to_close     |
                                   +----------+-----------+
                                              |
                                              | /goalspec close
                                              v
                                   +----------------------+
                                   |       closing        |
                                   +----------+-----------+
                                              |
                                              | 交付成功
                                              v
                                   +----------------------+
                                   |        closed        |
                                   +----------------------+

恢复环：

running -------------------------------> reopen_required
ready_to_close ------------------------/
reopen_required -- reopen-impact + re-review + re-approve + freeze --> ready_to_run

any state -----------------------------> blocked
blocked -------------------------------> blocker 解决后恢复生命周期
```

## 生命周期概览

主生命周期：

```text
no_goal
  -> intake_collecting
  -> spec_drafting
  -> awaiting_human_confirmation
  -> ready_to_run
  -> running
  -> ready_to_close
  -> closing
  -> closed
```

恢复状态：

```text
blocked
reopen_required
```

带恢复环的端到端流程：

```text
no_goal
  -> intake_collecting
  -> spec_drafting
  -> awaiting_human_confirmation
  -> ready_to_run
  -> running
  -> ready_to_close
  -> closing
  -> closed

running ---------> reopen_required --re-review / re-approve / freeze--> ready_to_run
ready_to_close --/

any state -------> blocked --------resolve blocker---------------------> lifecycle resumes
```

`reopen_required` 不是第二条实施通道，也不是回到 intake 的快捷方式。它是一个契约重审环。

## 分阶段说明

### `no_goal`

- 工作：当前没有活动中的 Goalspec 变更。
- 目的：保持一个安全的空闲状态。
- 人类：可以开始新的正式变更。
- AI：不能从闲聊里自行发明一个 `Goal`。
- 允许动作：`/goalspec start <intent>`。
- 退出条件：人类显式开始。

### `intake_collecting`

- 工作：采集意图和已批准的 source 材料。
- 目的：在冻结任何内容前，先把“要解决什么问题”采清楚。
- 人类：持续澄清意图、按需加入 source，最后结束 intake。
- AI：采集 source，但不写业务代码，也不冻结工件；对话由 `/goalspec end` 时从 session transcript 自动切片记录，无需手动记录。
- 允许命令：`/goalspec source <path>`、`/goalspec end`。
- 退出条件：显式 `/goalspec end`。
- 禁止：compile、freeze、run、close、业务代码修改。

### `spec_drafting`

- 工作：AI 基于 intake package 起草 `Goal`、`Criteria`、`Constraints`、out-of-scope 和 blocking questions。
- 目的：把采集到的意图转成可审查的契约草案。
- 人类：审阅草案内容。
- AI：必须主动把起草好的 `Goal / Criteria / Constraints` 展示给人类审阅。
- 允许动作：review、修订、回答 blocking questions、批准 intake package、apply suggestions、compile。
- 退出条件：经过审阅的 contract 草案进入 `awaiting_human_confirmation`。
- 禁止：实施。

### `awaiting_human_confirmation`

- 工作：草拟的 `Goal / Criteria / Constraints` 等待人类显式确认。
- 目的：确保只冻结经人类确认的验收口径。
- 人类：确认或修改 `Goal / Criteria / Constraints`。
- AI：吸收审阅反馈，然后等待显式确认后再 freeze。
- 允许动作：review、approve、freeze。
- 退出条件：成功 `freeze`。
- 禁止：实施。

### `ready_to_run`

- 工作：`Goal`、`Criteria`、`Constraints` 和 `Prompt` 都已冻结且是 fresh 的。
- 目的：建立稳定的执行基准。
- 人类：决定是否开始实施。
- AI：等待显式 `/goalspec run`。
- 允许命令：`/goalspec run`。
- 退出条件：allowed run 进入 `running`。
- 禁止：AI 自启实施。

### `running`

- 工作：一个 `Subagent` 实施；`Master Agent` 基于 evidence 判定 `Criteria`。
- 目的：让所有必需 `Criteria` 获得 fresh pass verdict。
- 人类：可以停止、澄清，或者在契约错误时要求 reopen。
- AI：执行 `Master Evaluation -> Subagent Work -> Evidence/Progress Report` 循环。
- 允许动作：实施、收集 evidence、生成 Master verdict。
- 退出条件：
  - 所有必需 `Criteria` fresh-pass -> 下一次 `/goalspec run` 生成 close package -> `ready_to_close`；
  - 契约错误/不足 -> `/goalspec reopen <reason>` -> `reopen_required`。
- 禁止：没有 Master verdict 就声明完成。

### `ready_to_close`

- 工作：所有必需 `Criteria` 都已有 fresh Master pass verdict，且 close package 已存在。
- 目的：在所有对外动作之前，先停下来做人工交付审阅。
- 人类：审阅 close package，并决定是否 close。
- AI：展示 close package 并等待。
- 允许命令：`/goalspec close`。
- 退出条件：显式 close 进入 `closing`。
- 禁止：自动 close。

### `closing`

- 工作：final verification、memory patch 应用、归档、分支、commit、push、PR、metadata。
- 目的：让交付具备原子性和可恢复性。
- 人类：如果失败，需要重新运行 `/goalspec close`。
- AI：报告 blocker 和基于 checkpoint 的 next action。
- 允许命令：`/goalspec close`（resume）。
- 退出条件：交付成功进入 `closed`。

### `closed`

- 工作：这次变更已经完全收口。
- 目的：成为唯一允许开启下一次正式变更的状态。
- 人类：可以开始下一次变更。
- AI：只把这个状态视为真正 done。
- 允许动作：`/goalspec start <intent>`。

### `blocked`

- 工作：流程被外部条件或操作性 blocker 停住。
- 目的：表达“契约仍然是对的，但现在暂时做不下去”。
- 典型原因：环境损坏、依赖不可用、权限缺失、外部系统故障。
- 人类：解决 blocker。
- AI：不重写 contract；只报告 blocker 并等待。

### `reopen_required`

- 工作：冻结后的 `Goal / Criteria / Constraints` 已经不再可接受。
- 目的：使当前 frozen execution basis 失效，并强制进入契约重审。
- 典型原因：缺失关键验收场景、约束互相冲突、Goal 定义错误、人类新的决定改变了“何为完成”。
- 人类：审阅 reopen impact，修改 `goal.md` 和/或 `contract.yaml`，然后重新 review、approve、freeze。
- AI：解释 reopen 原因，起草 contract 修改建议，并等待人类确认。不得继续沿用旧 basis 实施、judge 或 close。
- 退出条件：re-review / re-approve / `freeze` 把变更带回 `ready_to_run`。
- 禁止：直接 `/goalspec run`、`judge`、`complete`、`close`。

## Workflow

1. `/goalspec start <intent>` 打开正式 intake 窗口。
2. `/goalspec source <path>` 在 intake 打开时加入文件或目录 source。
3. `/goalspec end` 关闭 intake。
4. `/goalspec end` 之后，AI 起草 `Goal`、`Criteria`、`Constraints`、out-of-scope 和 blocking questions，展示给人类，并等待显式确认。
5. 人类确认后，冻结审核过的 `Goal`、`Criteria`、`Constraints`，并生成 `.goalspec/active/goal-driven-prompt.md`。确认本身不会启动实施。
6. `/goalspec run` 开始实施。
7. 所有必需 `Criteria` 拿到 fresh Master pass verdict 后，`/goalspec run` 生成 `.goalspec/active/close-package.yaml` 并进入 `ready_to_close`。
8. `/goalspec close` 确认当前 close package 并执行正式交付。

## 人工审核门禁

`start`、`end`、`run`、`close` 都是人工门禁命令。

AI 工具只能把它们当作人类显式 `/goalspec ...` 命令的直接翻译来执行：

- 不能因为“意图看起来已经采完了”就自己运行 `intake end`；
- 不能因为“Criteria 看起来满足了”就自己运行 `run`；
- 不能因为“close package 已经存在”就自己运行 `close`。

普通的“确认”“继续”“ok”或沉默，都不能替代这些命令。

此外，在 `/goalspec end` 和 `freeze` 之间还有一层审阅义务：AI 必须主动把起草好的 `Goal / Criteria / Constraints` 包展示给人类，并等待显式确认后才能 freeze。

## Run gate

`/goalspec run` 只有在所有前置条件都满足时才允许执行：

- `Goal`、`Criteria`、`Constraints` 已冻结；
- 没有未解决的 blocking questions；
- `Goal-Driven Prompt` 存在；
- frozen artifact hashes 与 prompt hash 都是当前的；
- effective scope hash 与 `state.yaml.scope_hash` 一致（没有未批准的路径扩展；见 [Scope amendments（范围修订）](#scope-amendments范围修订)）；
- 当前状态不是 `reopen_required`。

允许执行时的典型输出：

```text
GOALSPEC_RUN_ALLOWED: true
PROMPT_FILE: .goalspec/active/goal-driven-prompt.md
PROMPT_HASH: sha256:...
READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true
```

当所有必需 `Criteria` 都通过后，`run` 的输出会改为：

```text
CLOSE_PACKAGE_READY: true
CLOSE_PACKAGE_FILE: .goalspec/active/close-package.yaml
CLOSE_PACKAGE_HASH: sha256:...
NEXT_USER_ACTION: Review the close package, then run /goalspec close to archive, commit, push, and open a PR.
```

被阻止时的输出会包含 `GOALSPEC_RUN_ALLOWED: false`、`BLOCKER` 和 `NEXT_USER_ACTION`。

## 运行循环与停止条件

`/goalspec run` 不是一次性动作。当它返回 `GOALSPEC_RUN_ALLOWED: true` 时，Goal-Driven Prompt 会驱动 agent 会话进入循环：

```text
Master Evaluation -> Subagent Work -> Evidence/Progress Report
```

直到触发下面四个停止条件之一。这个循环发生在**单次** `/goalspec run` 内部；Goalspec 没有单独的 `loop` 命令。

停止条件，全部由循环无法绕过的 CLI 门禁（`run` / `judge apply`）强制执行：

1. **所有必需 Criteria 通过** —— 下一次 `/goalspec run` 生成 close package，并交给 `/goalspec close`。
2. **迭代上限（token 止损）** —— 每次 `judge apply`（一条 Master verdict = 一轮）会让 `state.run_loop.iteration` 自增。达到 `profile.run_loop.max_iterations`（默认 8）时，循环被标记为 `capped`：此后的 `run` 和 `judge apply` 都会被拒绝，直到人类执行 `/goalspec close` 或 `/goalspec reopen` 来重置它。上限从 profile 读取，因此是在循环运行**之前**就定好的。
3. **无进展（stalled）** —— `judge apply` 还会记录一份 verdict 指纹（每个 criterion 的最新 verdict，按 contract 顺序）以及当前的 evidence hash。如果两者连续 `profile.run_loop.stall_threshold`（默认 3）轮都不变，循环被标记为 `stalled`。`capped` 表示预算耗尽（close，或调高上限）；`stalled` 表示循环正卡在一个无法解决的 spec 缺陷上（reopen）。双重条件——verdict 和 evidence 都不变——正是为了让正常的多次迭代不被误杀：只要还有任何 verdict 在动，循环就在进展。所有必需 Criteria 已通过时豁免。
4. **judgment 类 Criteria** —— 一旦所有 `machine` criterion 都拿到 pass verdict，循环就不会再盲目重试剩余的 `judgment` 类 criteria；它们需要人工/Master 解决，而不是 Subagent 迭代。

`status` 会通过 `NEEDS_HUMAN_CONFIRMATION` 和针对性的 `NEXT_USER_ACTION` 暴露 `capped`/`stalled`。

### 无人值守地驱动循环

Goalspec 不内置调度器。如果想让循环在没有人类逐次输入 `/goalspec run` 的情况下推进，从外部驱动它即可——上面的停止条件会让它保持有界：

- Claude Code 的 `/loop`，或 cron/CI 按节奏调用 `.goalspec/goalspec run`。

只有 `frozen -> ready_to_close` 这段执行区间会被循环。人工门禁（`start` / `end` / `close`）永远不会被自动越过。

```yaml
# .goalspec/project/profile.yaml
run_loop:
  max_iterations: 8     # 触发 capped 前的 judge-apply 轮数
  stall_threshold: 3    # 触发 stalled 前连续无变化的轮数
```

## 循环工程可观测性（Loop engineering observability）

运行循环是可观测、且会自我记录的。在 Master/Subagent 循环之上叠加了四层机制——它们都不改变成功条件（Criteria 通过），而是记录循环尝试过什么、闭合“自述即通过”的缺口，并让一次确认的失败留下改进建议，而不是在沉默中空转。

### Sensor 校验（闭合自述缺口）

`profile.commands.{test,build,lint,typecheck}` 只在 `/goalspec close` 时运行。如果没有中间检查，一条 `pass` verdict 可能只是建立在 Subagent 自述的 `exit_code` 上。sensor 在 `judge apply` 时闭合这个缺口：

- 对 **pass** verdict 引用的每一条 `evidence_ref`，如果该 evidence 标记为 `reproducible: true`，sensor 会在项目根目录重跑该 evidence 的 `command`。
- 退出码非 0 → 该 verdict 被**拒绝**（不会自动降级）。Master 仍然是唯一的 verdict 作者。
- 只有 `reproducible: true` 的 evidence 会被重跑——这是为了副作用安全。负向 verdict 永远不会触发 sensor。schema 会拒绝 `reproducible: true` 但 `command` 为空的情况。

```yaml
# evidence.yaml —— reproducible evidence 会在 judge 时被 sensor 重新校验
- id: ev_01
  criteria_refs: ["c1"]
  command: "pytest -q tests/test_c1.py"
  exit_code: 0
  reproducible: true        # 有副作用（网络、写盘）的 evidence 设为 false
```

### trace.yaml（逐轮审计轨迹）

每次 `judge apply`（一条 Master verdict = 一轮）都会向 `.goalspec/active/trace.yaml` 追加一条记录：

```yaml
- iteration: 3
  judged_at: "2026-06-21T10:05:00Z"
  criterion_ref: c2
  verdict: fail
  master_reasoning: "..."
  evidence_diff: ["ev_04"]          # evidence hash 变化时当前存在的 evidence id
  stop_check:
    outcome: continue               # continue | capped | stalled
    why: "iteration 3 < max_iterations=8"
  contract_hash: sha256:...
  prompt_hash: sha256:...
```

`trace.yaml` 是只追加的历史记录，会在 close 时随 `active/` 一并归档。

### trajectory（派生的循环状态）

每一轮，Goalspec 都会重算 `state.run_loop.trajectory`——这是从 `verdict.yaml` + contract 纯派生出来的，不需要 Master 输入：

```yaml
run_loop:
  trajectory:
    tried_paths: ["c1=pass", "c2=fail"]
    failed_approaches: ["c2=fail"]
    current_blocker: "c2: fail - <reason>"
    next_step: "c2"
```

### harness-improvement-candidate.yaml（建议性，人工 gated 提升）

当循环命中一次确认的失败（`capped` 或 `stalled`）时，Goalspec 会生成 `.goalspec/active/harness-improvement-candidate.yaml`（幂等：每个 active goal 至多一条）。框架只填写失败溯源——`failure_kind`、`task_signature`、`failure_step`，以及 `rule_version`（含失败所依据的 `master.md` hash）：

```yaml
status: proposed               # proposed | under_review | promoted | rejected
failure_kind: stalled          # capped | stalled
task_signature:
  repeatedly_failing_criteria: ["c2"]
failure_step:
  iteration: 6
  refused_criterion: c2
  validator_reason: "no progress for 3 consecutive rounds ..."
rule_version:
  contract_hash: sha256:...
  prompt_hash: sha256:...
  master_md_hash: sha256:...   # 规则版本溯源
proposed_target: {}            # 留给 MASTER/HUMAN —— 改哪个规则文件
prediction: ""                 # 留给 MASTER/HUMAN —— 可证伪的陈述
reviewed_by_human: false
promoted: false                # 只有人类才能置 true，且须在回归通过后
```

提升是**人工门禁**的：框架永远不会填写 `proposed_target` / `prediction`，也永远不会把 `promoted` 置为 `true`。它是建议性的——循环为自己的失败留下证据，是否据此行动由人类决定。

### LOOP_CONTRACT（只读的 status 视图）

当契约已冻结时，`status` 末尾会追加一个 11 项的 loop-contract 视图——由 `goal.md` / `contract.yaml` / `profile.yaml` / `state.yaml` 组装而成，不写盘：

```text
LOOP_CONTRACT:
  name: <active_goal_id>
  trigger: /goalspec run (state=running)
  goal: <goal.md Intent 首行>
  input: contract.yaml (frozen), evidence.yaml, verdict.yaml, trace.yaml
  scope: <allowed_paths>
  tools: <profile 的 test/build/lint/typecheck>
  verification: profile 命令在 /goalspec close 时跑；sensor 在 judge apply 时重跑 reproducible evidence
  stop: max_iterations=8, stall_threshold=3, judgment-kind 门禁, all-required-pass
  escalation: /goalspec reopen <reason>（capped -> close 或 reopen；stalled -> reopen），/goalspec close（人工门禁）
  state: iteration=3, last_outcome=continue, trajectory={...}
  cleanup: close 把 active/ 归档到 history/vNNNN/、应用 memory-patch、重置 run_loop
```

它的作用是让循环的契约可以在一处被检视：什么触发它、什么喂给它、何时停止、向哪里升级。

## Reopen policy

只有在冻结后的 `Goal`、`Criteria` 或 `Constraints` 本身错误、不足、互相矛盾、在当前边界下不可实现，或已经和人类真实的验收口径冲突时，才使用 `/goalspec reopen <reason>`。

普通的“实现还没做完”不应该使用 reopen。如果 contract 仍然是正确的，只是工作尚未完成，就应继续留在 `running` 里推进 Master/Subagent 循环。

### Reopen 之后会发生什么

- 当前的 frozen execution basis 立即失效。
- 当前 frozen contract 会被降回 `draft`，必须重新 review、approve、freeze。
- 旧 `Prompt` 不得继续执行。
- `reopen-impact.yaml` 成为必需的恢复工件：必须填写、由人类确认，然后再修改 Goal/contract 并 freeze。
- 旧的 evidence 和 verdict 文件可以保留为历史，但不能自动证明修订后的 contract。
- 旧 close package 失效，不得 close。
- 生命周期返回到 contract re-review 和 re-freeze，然后才能恢复实施。

### Reopen 不等于“全部重做”

Goalspec 记录完成情况的单位，是 `Criteria / evidence / verdict`，不是任务清单。

`/goalspec reopen` 现在会创建 `.goalspec/active/reopen-impact.yaml` 作为正式恢复工件。重新 freeze 之前，必须完成它：

- 总结为什么 frozen contract 已不再可接受；
- 把 `Criteria` 分类为 `unchanged`、`modified`、`added`、`removed`；
- 列出哪些代码可以复用；
- 列出哪些 evidence 需要刷新；
- 区分 `rejudge_only` 和 `reimplement_needed`。

因此，reopen 应该驱动的是**按 Criteria 做 impact analysis**，而不是盲目整单重跑：

- `unchanged` Criteria：保留原 `Criterion ID`；如仍有效则复用代码；按需 re-judge 或 replay evidence。
- `modified` Criteria：重新 judge；必要时扩展实现或 evidence。
- `added` Criteria：新增实现和 evidence。
- `removed` Criteria：从 required completion set 中移除。

只有当 `Goal / Constraints` 的变化具有全局效应时，才应触发全量 re-validation。

### Reopen 与下一次变更的分界

如果人类提出的是一个**不会改变当前 Goal 是否完成**的额外增强项，更好的做法是：

1. 先 close 当前变更；
2. 再开始新的 `/goalspec start <intent>`。

如果新要求会改变“当前 Goal 何时算完成”，则应 reopen 当前变更，而不是开新一轮。

## Scope amendments（范围修订）

Scope 是 Constraints 的投影：`contract.yaml` 中的 `allowed_paths` 与 `forbidden_paths`。每一个被改动的业务文件都必须匹配某个 allowed 模式、且不匹配任何 forbidden 模式，否则 `/goalspec run` 的 close-readiness 与 `scope-check` 会拒绝。Scope 的 hash 会记入 `state.yaml.scope_hash`，因此任何未批准的路径扩展都会让 `run` 与 close-readiness 像其它 frozen 工件一样变 stale。

当实施确实需要触碰一些**仍然服务于当前 Goal、但不改变 Goal、Criteria 或语义 Constraints** 的路径时，记录一次人工批准的扩展，而不是 reopen：

```text
.goalspec/goalspec scope amend --allow <glob> [--allow <glob> ...] --reason <why>
```

这是 Constraints 投影通道；`/goalspec reopen` 是契约通道。这个区分是有意的：`scope amend` 只向 `.goalspec/active/scope-amendments.yaml` 追加一条 `approved` 修订，绝不覆盖 `contract.yaml`；而 `reopen` 会把冻结的 contract 降回 `draft`，并强制 re-review / re-approve / re-freeze。因此 `scope amend` 会：

- 要求 `--reason` 和至少一个 `--allow` glob；
- 拒绝任何会授权同时被 `forbidden_paths` 命中路径的 glob；
- 记录新旧 `scope_hash`（修订条目和 `state.yaml` 各一份）；
- 若 `.goalspec/active/goal-driven-prompt.md` 已存在则重新生成它（prompt 内嵌有效 scope，因此 `prompt_hash` 也会变）；
- 若变更已进入 `ready_to_close` 或 `closing`，则回滚到 `running` 并清空 `close_package_hash`，使下一次 `/goalspec run` 重新生成 close package。

只有 Goal、Criteria 或语义 Constraints 本身改变时才用 `reopen`；当 Goal 与 contract 仍然正确、只是 allowed-path 表太窄时，用 `scope amend`。

随时查看有效表：

```text
.goalspec/goalspec scope effective
```

它会打印 `allowed_paths`（contract 模式加上已批准的修订）、`forbidden_paths`，以及当前的 `scope_hash`。

## Close

`/goalspec close` 是唯一面向用户的收口命令。它确认当前 close package，并授权执行配置好的交付模式：

1. 校验 close package，并重新计算所有绑定 hash（contract、evidence、verdict、memory-patch、changed-files、suggested delivery、close package）。
2. 运行 final verification（来自 `.goalspec/project/profile.yaml` 的 test/build/lint/typecheck）。
3. 扫描 secrets、大文件和不允许的临时文件。
4. 再次执行 scope-check。
5. 把 memory patch 应用到 `.goalspec/project/**`。
6. 把 active 文件归档到 `.goalspec/history/vNNNN/`，并更新 `project/versions.yaml`。
7. 执行配置好的交付模式：
   - `github_pr`：创建或复用交付分支，commit、push、打开 PR，再记录交付 metadata。
   - `push_only`：创建或复用交付分支，commit、push，记录交付 metadata，但不创建 PR。
   - `local_commit`：创建本地 commit 和交付 metadata，不要求 remote 或 `gh`。
   - `archive_only`：只归档并收口，不做 git commit、push 或 PR。
8. 进入 `closed`。

Close 是可恢复的。如果它中途失败，会停在 checkpoint；再次运行 `/goalspec close` 会从断点继续，而不会重复创建主 commit。只要任何绑定 hash 在生成后发生变化，close package 就会 stale（被拒绝），此时必须重新运行 `/goalspec run` 来生成新的 package。

AI 工具不得用手写 `git add`、`git commit`、`git push`、`gh pr create`、手工归档或直接写 `status: closed` 的方式替代 `/goalspec close`。如果需要非 GitHub 或本地交付，请在 `.goalspec/project/profile.yaml` 显式设置 `delivery.mode`。如果失败，只能报告 CLI 给出的 blocker 和 next user action。

Close 不负责自动 merge PR、创建 release、打 tag 或部署。这些都不在其范围内。

### 交付模式（Delivery modes）

交付模式在 `.goalspec/project/profile.yaml` 中显式配置：

```yaml
delivery:
  mode: github_pr   # github_pr | push_only | local_commit | archive_only
  remote: origin
  base_branch: main
```

`github_pr` 是默认值，这样既有的项目不会在不知不觉中降级交付。非 GitHub 或纯本地项目应在生成 close package 之前选择 `push_only`、`local_commit` 或 `archive_only`。

## Execution model

生成的 `Prompt` 定义了一个 `Master Agent` 和一个 `Subagent`。

- `Subagent` 在冻结后的 `Goal` 和 `Constraints` 下工作。
- `Master Agent` 严格依据冻结后的 `Criteria` 判定进度。
- 内部尝试、execution scope、测试轮次和实现步骤都不是成功标准。
- `Criteria` 满足才是唯一成功条件。
- 如果在执行中发现 `Goal`、`Criteria` 或 `Constraints` 有问题，必须停止并请求 `/goalspec reopen <reason>`。

如果 AI 工具不支持显式 `Subagent`，则必须显式模拟下面这个流程：

```text
Master Evaluation
Subagent Work
Evidence/Progress Report
Master Evaluation
```

## Criteria

`criteria:` 下的所有条目默认都是 required，不要重复写 `required: true`。

如果只是有价值但不应该阻塞 closure 的想法，请写到 `optional_criteria:`。

每条 required criterion 都必须满足：

- 清晰；
- 可以从 evidence 判定；
- 与 `Goal` 直接相关；
- 保持最小，不夹带实现步骤或技术选型。

## Evidence and completion model

Evidence 记录的是可观察事实，并把这些事实绑定到 `Criteria`。`Subagent` 可以产生 evidence。

标记为 `reproducible: true` 的 evidence 会带上一个 `command`，sensor 在 `judge apply` 时会重跑它来确认 pass verdict（见[循环工程可观测性](#循环工程可观测性loop-engineering-observability)中的 Sensor 校验小节）。有副作用（网络、写盘）的 evidence 应标记为 `reproducible: false`。

只有 `Master Agent` 可以给出最终 verdict。`Subagent` 的自述、测试通过或 evidence 文本本身，都不能直接关闭目标。

系统对完成情况的记录方式是：

- `criteria_ref` -> `evidence.yaml` 中的 evidence 绑定；
- 每个 `criteria_ref` 在 `verdict.yaml` 中的最新 Master verdict。

Goalspec **不会**把内部任务清单、work units 或实现步骤当作“完成单位”。

要满足 closure，必须同时满足：所有必需 `Criteria` 都有 fresh pass verdict、`Constraints` 仍被遵守、`.goalspec/active/close-package.yaml` 是当前的、final verification 通过，并且 `.goalspec/goalspec close` 成功完成交付。

## Status

任何时候不确定，就运行 status：

```bash
.goalspec/goalspec status
```

它会报告 `STATE`、`GOAL`、`FROZEN`、`PROMPT_READY`、`RUN_ALLOWED`、`CLOSE_READY`、`NEEDS_HUMAN_CONFIRMATION`、`BLOCKERS`、`CLOSE_BLOCKERS`、`UNMET_CRITERIA`、`SCOPE_HASH` 和 `NEXT_USER_ACTION`。契约冻结后还会追加 `LOOP_CONTRACT:` 视图（见[循环工程可观测性](#循环工程可观测性loop-engineering-observability)）。
