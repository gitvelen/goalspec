# Goalspec Enhance V2: 从 Goal-Driven 执行到一键收口

> 状态：设计方案。本文是在 `goalspec_enhance.md` 已落地的 Goal-Driven Prompt 框架基础上，补齐“验收后如何收口、交付、进入下一次变更”的二阶段优化方案。

## 1. 目标

Goalspec V2 不只要保证 AI 工具按冻结后的 Goal、Criteria、Constraints 实施，还要保证一次变更在验收通过后能被完整收口。

框架需要稳定完成六件事：

1. 在明确 intake 窗口内承接用户真实意图。
2. 将用户意图转化为清晰的 Goal、Criteria 和 Constraints。
3. 只有在人类显式确认后，才能冻结 Goal、Criteria 和 Constraints。
4. 只有在人类显式输入 `/goalspec run` 后，才能执行冻结后的 Goal-Driven Prompt。
5. 在 Criteria 全部通过后，生成可审阅的 close package。
6. 只有在人类显式输入 `/goalspec close` 后，才能执行长期记忆更新、历史归档、commit、push 和 PR 创建，并进入可开启下一次变更的终态。

核心不变量：

```text
AI 工具不得执行“任务清单”。
AI 工具必须执行冻结后的 Goal-Driven Prompt。
AI 工具不得自评完成。
AI 工具不得绕过 Goalspec CLI 手动收口。
只有 closed 状态才允许开启下一次变更。
```

## 2. 公开模型

公开模型仍然以三个权威产物为核心：

```text
Goal        用户的最终目标
Criteria    判断 Goal 是否达成的成功标准
Constraints AI 执行时不得违反的边界
```

V2 新增一个用户可理解的收口产物：

```text
Close Package    验收通过后，AI 准备交付本次变更的收口包
```

Close Package 不是新的成功标准。它是用户执行 `/goalspec close` 前看到并确认的交付计划，包含：

- Goal 摘要。
- required Criteria 的 verdict 摘要。
- evidence 和验证命令摘要。
- 变更文件摘要。
- memory patch。
- 建议 commit message。
- 建议 PR title/body。
- 风险、未做事项和 follow-up。
- 本次 close package 绑定的 hash。

用户输入 `/goalspec close` 即表示确认当前 close package，并授权 Goalspec 执行完整收口。

## 3. 用户命令面

V2 用户命令面如下：

```text
/goalspec start <intent>
/goalspec source <path>
/goalspec end
/goalspec run
/goalspec close
/goalspec status
/goalspec reopen <reason>
```

`/goalspec close` 是唯一用户可见收口命令。

以下命令可以作为内部命令存在，但不应作为普通用户流程教学：

```text
compile
approve
freeze
review
evidence
judge
complete
scope-check
validate
```

不应引入 `/goalspec ship`。`ship` 和 `close` 的区别过细，会增加用户心智负担。V2 中统一使用 `/goalspec close` 表示“验收通过后，把本次变更完整收口到可开启下一次变更的状态”。

## 4. 生命周期

V2 生命周期如下：

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

### 状态含义

`no_goal`：没有活动目标，可以运行 `/goalspec start <intent>`。

`intake_collecting`：正式 intake 窗口已打开，可以继续补充意图或 source。

`spec_drafting`：intake 已关闭，AI 正在起草 Goal、Criteria、Constraints、out-of-scope 和 blocking questions。

`awaiting_human_confirmation`：等待用户确认或修改 Goal、Criteria、Constraints。

`ready_to_run`：Goal、Criteria、Constraints 已冻结，Goal-Driven Prompt 已生成且未 stale，可以运行 `/goalspec run`。

`running`：AI 正在执行冻结后的 Goal-Driven Prompt。实施、evidence、Master verdict 都属于此阶段的内部循环。

`ready_to_close`：required Criteria 已全部由 Master verdict 判定为 pass，Constraints 未违反，AI 已生成 close package，等待用户运行 `/goalspec close`。

`closing`：`/goalspec close` 正在执行。Goalspec 正在做最终验证、长期记忆更新、history 归档、commit、push 和 PR 创建。

`closed`：本次变更已经完整收口。只有该状态允许开启下一次 `/goalspec start <intent>`。

`blocked`：当前流程因外部条件或失败停住，需要用户或环境处理。

`reopen_required`：执行中发现 Goal、Criteria 或 Constraints 本身错误或不足，必须重新审阅冻结产物。

### 移除或弱化的状态

V2 不再把 `judging_or_continuing` 作为用户可见状态。判断和继续是 `running` 内部的 Master/Subagent 循环。

V2 不再使用 `completed` 作为终态。`completed` 容易让用户误解为“代码写完了”，但它不保证 commit、push、PR 或工作区干净。V2 的唯一终态是 `closed`。

## 5. `/goalspec run`

`/goalspec run` 仍然是唯一实施入口。

当用户输入 `/goalspec run` 时，AI 工具必须：

1. 运行项目本地 `.goalspec/goalspec run`。
2. 如果输出 `GOALSPEC_RUN_ALLOWED: false`，立即停止。
3. 如果输出 `GOALSPEC_RUN_ALLOWED: true`，完整读取 `.goalspec/active/goal-driven-prompt.md`。
4. 将 frozen Goal、Criteria、Constraints 作为当前执行权威。
5. 执行 Master Agent / Subagent 循环。
6. 记录 evidence。
7. 由 Master 基于 fresh evidence 逐条生成 verdict。
8. Criteria 未全部 pass 时继续驱动 Subagent 工作。
9. Criteria 全部 pass 后生成 close package，并进入 `ready_to_close`。

`/goalspec run` 不应自动执行 commit、push 或 PR。

`/goalspec run` 完成验收后，AI 应输出类似：

```text
验收已通过，已生成 close package。
运行 /goalspec close 后，我会应用长期记忆、归档 history、commit、push 并创建 PR。
```

## 6. Close Package

Close Package 是 `/goalspec close` 的统一确认对象。

### 生成时机

AI 工具在以下条件全部满足后生成 close package：

- Goal、Criteria、Constraints 仍然 frozen 且未 stale。
- 不存在 unresolved blocking questions。
- required Criteria 均有 Master `pass` verdict。
- 每个 pass verdict 都引用 fresh evidence。
- scope-check 通过。
- Subagent 没有修改 forbidden authority files。
- AI 已生成 memory patch。
- 已生成建议 commit message 和 PR title/body。

生成 close package 后，状态进入 `ready_to_close`。

### 必须包含的内容

Close Package 应至少包含：

```yaml
goal_id:
goal_summary:
criteria_verdicts:
  - criteria_ref:
    verdict:
    evidence_refs:
verification:
  commands:
    - command:
      exit_code:
      summary:
changed_files:
  business:
  goalspec:
memory_patch:
  patches:
commit:
  message:
pr:
  title:
  body:
risks:
  residual:
  follow_ups:
hashes:
  contract_hash:
  evidence_hash:
  verdict_hash:
  memory_patch_hash:
  changed_files_hash:
  close_package_hash:
```

具体文件建议为：

```text
.goalspec/active/close-package.yaml
```

可选再生成便于用户阅读的 Markdown：

```text
.goalspec/active/close-package.md
```

### Hash 绑定

Close Package 必须绑定它所确认的事实：

- frozen contract hash。
- evidence hash。
- verdict hash。
- memory patch hash。
- changed files hash。
- suggested commit/PR text hash。

用户执行 `/goalspec close` 时，Goalspec 必须重新计算这些 hash。若任何 hash 不一致，close 必须拒绝，并要求重新生成 close package。

### 统一确认语义

用户输入 `/goalspec close` 表示：

```text
我确认当前 close package。
我授权 Goalspec 应用 memory patch。
我授权 Goalspec 归档 history。
我授权 Goalspec stage 本次变更相关文件。
我授权 Goalspec commit、push 并创建 PR。
```

因此 V2 不再要求用户单独运行 `approve memory-patch`。该动作可以保留为内部机制，但普通用户确认统一收敛到 `/goalspec close`。

## 7. `/goalspec close`

`/goalspec close` 是唯一收口入口。

它的目标是把状态从 `ready_to_close` 推进到 `closed`。成功后，本次变更必须具备开启下一次变更的条件。

### 前置条件

`/goalspec close` 必须在以下任一条件不满足时拒绝：

- 当前状态不是 `ready_to_close` 或可恢复的 `closing`。
- close package 缺失。
- close package stale。
- required Criteria 没有全部 pass。
- 存在 unresolved blocking questions。
- frozen Goal、Criteria、Constraints 或 Prompt stale。
- scope-check 失败。
- final verification 失败。
- 有无关 dirty files。
- 检测到疑似 secret、私钥、敏感 token。
- 检测到未授权大文件或临时文件。
- Git remote 缺失。
- 当前分支、目标分支或 PR base 无法确定。
- `gh` 或配置的 PR 工具不可用或未登录。
- push 或 PR 创建失败。

### 执行流程

Happy path：

```text
1. 读取 state，确认状态为 ready_to_close。
2. 读取并校验 close package。
3. 重新计算所有绑定 hash。
4. 运行 final verification。
5. 运行 secret / 大文件 / 临时文件检查。
6. 运行 scope-check。
7. 应用 memory patch。
8. 归档 active 文件到 history/vNNNN。
9. 更新 project/versions.yaml。
10. 写入 close summary。
11. 创建或确认工作分支。
12. stage 主 commit 文件集。
13. 创建主 commit。
14. push 工作分支。
15. 创建 PR，获取 PR URL。
16. 写入 delivery metadata。
17. 将状态设为 closed。
18. 创建元数据 commit。
19. 再次 push 工作分支。
20. 输出 commit、branch、PR URL、history version。
```

### 主 commit

主 commit 在 PR 创建前产生。

它应包含：

- 业务代码变更。
- 测试、构建或验证相关变更。
- `.goalspec/project/**` 长期记忆更新。
- `.goalspec/history/vNNNN/**` 历史归档。
- `.goalspec/active/close-package.*`。
- `.goalspec/active/state.yaml` 中除最终 delivery metadata 以外的 close 进度。

主 commit message 来自 close package。

主 commit 必须在 push 和 PR 创建之前完成，因为 PR 需要基于已推送分支创建。

### 元数据 commit

元数据 commit 在 PR 创建后产生。

原因是 PR 创建前无法知道：

- PR URL。
- PR number。
- remote branch 的最终名字。
- pushed main commit SHA。
- closed timestamp。

元数据 commit 应只包含交付事实，例如：

```yaml
delivery:
  status: closed
  history_version: v0001
  branch: goalspec/<goal-id>-<slug>
  base_branch: main
  remote: origin
  main_commit: <sha>
  metadata_commit: <sha or null-before-commit>
  pr_url: https://github.com/org/repo/pull/123
  closed_at: 2026-06-19T00:00:00Z
```

元数据建议写入：

```text
.goalspec/history/vNNNN/delivery.yaml
```

并可同步记录在：

```text
.goalspec/active/state.yaml
```

元数据 commit message 建议：

```text
chore(goalspec): record delivery metadata for <goal-id>
```

### 两个 commit 的必要性

V2 接受 `/goalspec close` 内部最多产生两个 commit。

如果强制一个 commit，会出现三种不理想方案：

- 不记录 PR URL，降低审计性。
- amend 主 commit 后 force-push，增加协作风险。
- PR 创建后留下本地 dirty metadata，导致不能安全开启下一次变更。

两个 commit 保持用户心智简单：用户仍然只执行一个 `/goalspec close`，内部 commit 数量是实现细节。

## 8. Checkpoint 和失败恢复

`/goalspec close` 必须是可恢复的。

Close 执行过程中应记录 checkpoint：

```yaml
close:
  status: not_started | verifying | completed_gate | main_committed | pushed | pr_created | metadata_committed | closed | failed
  history_version:
  main_commit:
  metadata_commit:
  branch:
  pr_url:
  failed_at:
  failure_reason:
```

如果 close 中途失败：

- 不得进入 `closed`。
- 不得允许开启下一次变更。
- 不得重复创建主 commit。
- 再次运行 `/goalspec close` 应从 checkpoint 继续。

示例：

```text
主 commit 已创建并 push，但 PR 创建失败。
用户修复 gh 登录后再次运行 /goalspec close。
Goalspec 应复用已有 main_commit 和 branch，继续创建 PR，而不是重新 commit。
```

失败恢复必须优先保证幂等性和可审计性。

## 9. 长期记忆

长期记忆位于：

```text
.goalspec/project/profile.yaml
.goalspec/project/memory.yaml
.goalspec/project/constraints.yaml
.goalspec/project/regression-suite.yaml
.goalspec/project/versions.yaml
```

### 内容分类

`profile.yaml` 存放项目事实：

- 语言。
- 框架。
- 包管理器。
- 运行时。
- 默认 test/build/lint/typecheck 命令。
- 必要服务。
- 必要环境变量。
- 本地 setup 注意事项。

`memory.yaml` 存放长期能力和决策：

- `capabilities`：项目已经具备的能力。
- `decisions`：未来应延续的技术或产品决策。

`constraints.yaml` 存放长期约束：

- 安全约束。
- 兼容性约束。
- 数据生命周期约束。
- 运行环境约束。
- 成本、权限、隐私、部署约束。

`regression-suite.yaml` 存放锁定回归：

- 历史问题。
- replay command。
- expected result。
- 状态。

`versions.yaml` 存放 Goalspec 完成历史索引：

- history version。
- goal id。
- close time。
- contract hash。
- PR URL 或 delivery metadata 引用。

### 使用规则

AI 工具在以下场景使用长期记忆：

- 起草新 goal/contract 时，用 `profile.yaml` 找验证命令和运行边界。
- 起草 Constraints 时，自动纳入 `constraints.yaml` 的长期约束。
- 起草 Criteria/evidence requirements 时，纳入 `regression-suite.yaml` 的 locked regressions。
- 起草方案时，用 `memory.yaml` 避免重复争论既定决策。
- 判断项目能力时，用 `capabilities` 避免把已有能力误判为新需求。

长期记忆不能覆盖本次 frozen Goal、Criteria、Constraints。若长期记忆和本次意图冲突，AI 必须提出 blocking question 或请求 `/goalspec reopen <reason>`。

## 10. AI Adapter 强制规则

AI 工具必须把用户命令映射到项目本地 CLI。

### `/goalspec run`

收到 `/goalspec run`：

```bash
.goalspec/goalspec run
```

然后完整读取 Goal-Driven Prompt 并执行。

### `/goalspec close`

收到 `/goalspec close`：

```bash
.goalspec/goalspec close
```

AI 工具不得手写替代流程：

- 不得自行运行一串 git add/commit/push/gh pr create 来替代 `goalspec close`。
- 不得直接编辑 state 为 `closed`。
- 不得绕过 close package hash 校验。
- 不得绕过 final verification。
- 不得在 close 失败后自行补执行未完成 git 步骤。

Close 失败时，AI 工具必须报告 CLI 输出的 blocker 和 next user action。

### 新变更门禁

收到 `/goalspec start <intent>` 时，AI 工具必须先运行 status。

只有状态为 `no_goal` 或 `closed` 时，才能开启新 goal。

如果状态不是 `closed`，且已有 active goal，必须拒绝开始新变更，并提示先完成、close 或 reopen 当前目标。

### 自然语言确认

普通“确认”只能确认当前等待确认的包：

- intake package。
- Goal/Criteria/Constraints。
- close package。

普通“继续”不得开始实施，除非用户明确包含 `/goalspec run`。

普通“继续”不得收口，除非用户明确包含 `/goalspec close`。

## 11. CLI 强制边界

V2 的可靠性不能依赖 AI 自觉。CLI 必须强制执行关键边界。

### `run`

`run` 只允许从 `ready_to_run` 进入 `running`。

如果 Goal、Criteria、Constraints、Prompt 任一 stale，拒绝。

### `close`

`close` 只允许从 `ready_to_close` 或可恢复的 `closing` 继续。

`close` 负责：

- 校验 close package。
- 运行最终验证。
- 应用 memory patch。
- 执行 completion gate。
- 归档 history。
- 创建 commit。
- push。
- 创建 PR。
- 写 delivery metadata。
- 设置状态 `closed`。

### `start`

`start` 只允许从：

```text
no_goal
closed
```

开始。

如果存在未 closed 的 active goal，必须拒绝。

### `status`

Status 输出面向用户，应包含：

```text
STATE:
GOAL:
FROZEN:
PROMPT_READY:
RUN_ALLOWED:
CLOSE_READY:
NEEDS_HUMAN_CONFIRMATION:
BLOCKERS:
UNMET_CRITERIA:
NEXT_USER_ACTION:
```

示例：

```text
STATE: ready_to_close
CLOSE_READY: true
NEXT_USER_ACTION: Review the close package, then run /goalspec close to archive, commit, push, and open a PR.
```

```text
STATE: closed
NEXT_USER_ACTION: Goal closed. Run /goalspec start <intent> for another change.
```

## 12. 安全和 Git 规则

### Branch

如果当前分支是 `main` 或 `master`，`/goalspec close` 应创建工作分支：

```text
goalspec/<goal-id>-<slug>
```

如果当前分支已经是非 protected 工作分支，可以继续使用当前分支。

如果无法判断目标分支，close 拒绝并要求用户配置或切换。

### Stage 范围

`/goalspec close` 只能 stage：

- 本次 Goal 的 allowed business paths。
- 本次生成或更新的 `.goalspec/active/**` 必要文件。
- `.goalspec/history/vNNNN/**`。
- `.goalspec/project/**`。
- AI adapter 管理文件中与本次框架状态必要相关的部分。

未被 contract allowed_paths 覆盖的业务文件必须阻断 close。

### Secret 检查

Close 前必须检查 staged 和 unstaged 变更中是否出现：

- 私钥。
- token。
- `.env` 实际密钥。
- 云服务凭证。
- SSH key。
- 大段 base64 可疑凭据。

发现疑似 secret 时，必须拒绝 close。

### Final Verification

Final verification 应从 `.goalspec/project/profile.yaml` 中读取命令：

- test。
- build。
- lint。
- typecheck。

如果 profile 没有命令，AI 可以在 close package 中记录“未配置验证命令”，但 close 是否允许通过应由项目配置决定。

推荐默认：

```text
如果没有任何验证命令，但 Criteria evidence 已经充分，close 可以继续，并在 close package 中记录 residual risk。
```

## 13. Human Gates

V2 明确三类人类门禁：

### Intake 确认

`/goalspec end` 后，AI 生成 intake capture 和 constraint suggestions。写入 `.goalspec/project/**` 前必须展示并等待用户确认。

### Freeze 确认

冻结 Goal、Criteria、Constraints 前，必须展示自然语言确认视图并等待用户确认。

确认只表示产物正确，不表示开始实施。

### Close 确认

`ready_to_close` 前，AI 必须展示 close package。

用户输入 `/goalspec close` 即表示确认该 close package，并授权完整收口。

如果 close package stale，`/goalspec close` 必须拒绝。AI 必须重新生成并展示 close package。

## 14. 文件和数据结构

建议新增：

```text
runtime/commands/close.sh
runtime/lib/close.sh
runtime/lib/git_delivery.sh
runtime/templates/active/close-package.yaml
runtime/templates/active/close-package.md
```

建议扩展：

```text
runtime/commands/status.sh
runtime/commands/run.sh
runtime/commands/new_goal.sh
runtime/commands/intake.sh
runtime/commands/complete.sh
runtime/lib/state.sh
runtime/lib/hash.sh
runtime/lib/scope.sh
runtime/lib/validate.sh
runtime/templates/active/state.yaml
runtime/templates/ai/core.md
runtime/templates/AGENTS.md
runtime/templates/CLAUDE.md
skills/goalspec/SKILL.md
skills/goalspec/references/command-map.md
README.md
```

`state.yaml` 建议增加：

```yaml
status: no_goal
close_package_hash: null
close:
  status: not_started
  history_version: null
  main_commit: null
  metadata_commit: null
  branch: null
  base_branch: null
  remote: null
  pr_url: null
  failed_at: null
  failure_reason: null
```

`history/vNNNN/delivery.yaml` 建议结构：

```yaml
status: closed
goal_id:
history_version:
branch:
base_branch:
remote:
main_commit:
metadata_commit:
pr_url:
closed_at:
close_package_hash:
verification_summary:
```

## 15. 实施阶段

### Phase 1: 生命周期和状态

- 将终态从 `completed` 改为 `closed`。
- 新增 `ready_to_close` 和 `closing`。
- 移除用户可见 `judging_or_continuing`。
- 更新状态迁移校验。
- 更新 `status` 输出。

### Phase 2: Close Package

- 新增 close package 模板。
- 增加 close package hash。
- 在 run loop 验收通过后生成 close package。
- 将状态置为 `ready_to_close`。
- close package stale 时阻断 close。

### Phase 3: Close Gate

- 新增 `goalspec close`。
- close 校验 required verdict、evidence、scope、memory patch、dirty files 和 final verification。
- close 将原 `complete` 门禁内部化。
- `/goalspec close` 作为 memory patch 的统一确认入口。

### Phase 4: Git Delivery

- 实现工作分支选择。
- 实现主 commit。
- 实现 push。
- 实现 PR 创建。
- 实现 delivery metadata。
- 实现元数据 commit。
- 实现失败 checkpoint 和续跑。

### Phase 5: AI Adapter

- 更新 Codex、Claude、Lingma adapter。
- `/goalspec close` 必须调用 `.goalspec/goalspec close`。
- 禁止 AI 手动替代 close。
- 禁止非 `closed` 状态开启新 goal。

### Phase 6: 文档和测试

- 更新 README。
- 更新 skill command map。
- 更新 `goalspec_enhance.md` 或将本文作为 V2 权威。
- 增加 close 相关 GOALC 测试。

## 16. 验收标准

### 用户命令

- README 和 help 包含 `/goalspec close`。
- README 不教学 `/goalspec ship`。
- README 不把 `complete` 作为普通用户命令。
- `/goalspec run` 仍然是唯一实施入口。
- `/goalspec close` 是唯一收口入口。

### 生命周期

- Criteria 全部 pass 后进入 `ready_to_close`。
- `/goalspec close` 执行时进入 `closing`。
- close 成功后进入 `closed`。
- 只有 `closed` 允许开启新 goal。
- 非 `closed` 状态下 `/goalspec start` 会拒绝已有 active goal。

### Close Package

- close package 包含 Goal、verdict、evidence、verification、changed files、memory patch、commit、PR、risk 和 hash。
- close package stale 会阻断 `/goalspec close`。
- `/goalspec close` 等价于用户确认当前 close package。

### Completion Gate

- required Criteria 缺少 pass verdict 时 close 失败。
- pass verdict 缺少 fresh evidence 时 close 失败。
- Constraints 或 scope 违规时 close 失败。
- blocking questions 未解决时 close 失败。

### Git Delivery

- close 成功会创建主 commit。
- close 成功会 push 工作分支。
- close 成功会创建 PR。
- close 成功会写入 PR URL。
- close 成功会创建元数据 commit。
- close 成功后工作区干净，或只剩明确允许的本地忽略文件。

### Failure Recovery

- 主 commit 已创建但 PR 失败时，不进入 `closed`。
- 再次运行 `/goalspec close` 不重复主 commit。
- 再次运行 `/goalspec close` 可从 checkpoint 继续。
- close 失败输出 blocker 和 next user action。

### AI Adapter

- AI 收到 `/goalspec close` 后只运行 `.goalspec/goalspec close`。
- AI 不手动替代 close 流程。
- AI 不直接写 `closed` 状态。
- AI 不在非 `closed` 状态开启下一次变更。

## 17. 非目标

V2 不解决以下问题：

- 自动发布到生产环境。
- 自动创建 GitHub Release。
- 自动打语义版本 tag。
- 自动合并 PR。
- 自动处理所有团队分支策略。
- 在没有 Git remote 的项目中强行完成 PR 交付。

这些可以作为后续能力，但不属于 V2 的默认 close 语义。

## 18. 最终用户心智

用户只需要理解三个核心动作：

```text
/goalspec start <intent>   开始定义变更
/goalspec run              开始实施并验收
/goalspec close            一键收口、commit、push、创建 PR
```

最终判断也只有一句：

```text
只有状态为 closed，才表示本次变更已经收口，可以开启下一次变更。
```
