# Goalspec — core rules

本项目使用 Goalspec 框架。

## 三个核心动作

用户只需理解三个动作：

```text
/goalspec start <intent>   开始定义变更
/goalspec run              开始实施并验收，验收通过后生成 close package
/goalspec close            一键收口：应用记忆、归档、commit、push、创建 PR
```

最终判断只有一句：**只有状态为 `closed`，才表示本次变更已经收口，可以开启下一次变更。**

开始任务前：

1. 运行或读取 `.goalspec/goalspec status`。
2. 按 `NEXT_USER_ACTION` 和冻结状态行动。
3. `/goalspec run` 前不得修改业务代码。
4. `/goalspec run` 允许后，必须完整读取 `.goalspec/active/goal-driven-prompt.md`，并将其中的 Goal、Criteria、Constraints 作为当前执行权威。
5. 不要自评完成。Criteria 判定只能来自 Master verdict；完整收口只能来自 `goalspec close`。
6. 不得用手写 git/gh 命令替代 `.goalspec/goalspec close`，也不得直接把状态写成 `closed`。
7. 非 `closed`/`no_goal` 状态下，不得开启下一次 `/goalspec start`。

## 权威链

- 意图只在 `.goalspec/active/goal.md`。
- intake package 只在 `.goalspec/active/intake-capture.md` 与 `.goalspec/active/constraint-suggestions.yaml`，确认前不能写入 `.goalspec/project/**`。
- Goal、Criteria、Constraints 只在 frozen `.goalspec/active/{goal,criteria,constraints}.yaml` 及其 hash 绑定中。
- 执行指令只在 `.goalspec/active/goal-driven-prompt.md`。
- 兼容契约只在 frozen `.goalspec/active/contract.yaml`。
- 事实只在 `.goalspec/active/evidence.yaml` 与 `.goalspec/active/trace.yaml`。
- Criteria 判定只在 `.goalspec/active/verdict.yaml`。
- 收口确认只在 `.goalspec/active/close-package.yaml` + `goalspec close`。
- 长期记忆只在 `.goalspec/project/*.yaml`。
- 交付事实只在 `.goalspec/history/vNNNN/delivery.yaml`。

聊天、commit message、测试输出、Subagent 自述都不是完成判据。

## 耐久性优于精确

写 Goal、Criteria、Constraints、Prompt 及任何执行 brief 时，遵守耐久性优于精确：

- 禁文件路径和行号——它们会过期，让审批与证据频繁 stale。描述接口、行为、类型契约。
- 写行为，不写过程——写系统该做什么（what），不写怎么实现（how）。
- 清晰 Criteria + 显式出界——每个验收点可独立验证；显式写出“不做什么”，防镀金。

实现步骤、函数名、类名、表结构、施工顺序是实现细节，不是意图或约束，默认不进 `goal.md`/`contract.yaml`（除非人类明确确认为目标约束）。这条与 hash 绑定权威互为支撑：引用会过期的位置，等于制造无谓的 stale。

## Close Package 与收口

当所有 required Criteria 都有 fresh Master pass verdict 后，再次运行 `.goalspec/goalspec run` 会生成 close package 并进入 `ready_to_close`。close package 绑定 contract/evidence/verdict/memory-patch/changed-files/delivery 的 hash——任一改变即 stale，`/goalspec close` 会拒绝并要求重新生成。

用户输入 `/goalspec close` 表示确认当前 close package，并一次性授权：应用长期记忆、归档 history、创建工作分支、主 commit、push、创建 PR、写 delivery metadata、元数据 commit，最后进入 `closed`。close 是可恢复的：中途失败会停在 checkpoint，再次运行 `/goalspec close` 从断点续跑，不重复主 commit。

AI 不得绕过 close package hash 校验、final verification、scope-check 或 CLI checkpoint；close 失败时只报告 CLI 输出的 blocker 与 next user action。
