# Goalspec — core rules

本项目使用 Goalspec 框架。

Goalspec 默认是显式启用（opt-in）模式。只有当人类明确发出 `/goalspec ...` 命令，或清楚表示要进入正式 Goalspec 变更流程时，你才进入该生命周期。否则按普通开发协作处理；你可以建议使用 Goalspec，但不得把普通请求擅自升级为 Goalspec 生命周期。

## 三个核心动作

用户只需理解三个动作：

```text
/goalspec start <intent>   开始定义变更
/goalspec run              开始实施并验收，验收通过后生成 close package
/goalspec close            一键收口：应用记忆、归档、执行已配置交付模式
```

最终判断只有一句：**只有状态为 `closed`，才表示本次变更已经收口，可以开启下一次变更。**

开始任务前：

1. 运行或读取 `.goalspec/goalspec status`。
2. 按 `NEXT_USER_ACTION` 和冻结状态行动。
3. `/goalspec run` 前不得修改业务代码。
4. `/goalspec run` 允许后，必须完整读取 `.goalspec/active/goal-driven-prompt.md`，并将其中的 Goal、Criteria、Constraints 作为当前执行权威。
5. Agent roles 只是执行协议：Master 直接控制 exactly one Primary Subagent；Primary Subagent 可在工具支持时委派 bounded、Criteria-linked Worker Subagents；这些角色不改变 Goal / Criteria / Constraints 三模型。
6. 不要自评完成。Criteria 判定只能来自 Master verdict；完整收口只能来自 `goalspec close`。
7. 不得用手写 git/gh 命令替代 `.goalspec/goalspec close`，也不得直接把状态写成 `closed`。
8. 非 `closed`/`no_goal` 状态下，不得开启下一次 `/goalspec start`。
9. `start`/`end`/`run`/`close` 是人类门禁：只有当人类显式发出对应 `/goalspec` 斜杠命令时，你才执行 `.goalspec/goalspec <cmd>`，绝不自启——不得因为"意图已采集完"就自己跑 `intake end`（草拟好 intake package 后停下，等人类敲 `/goalspec end`）；不得因为"Criteria 看起来满足"就自己跑 `run`；不得因为"close package 已存在"就自己跑 `close`。裸 "确认/继续/好的/沉默"都不等于这些斜杠命令；审批必须使用阶段化短语，如 `确认并应用 intake package` 或 `确认并冻结契约`。
10. 若用户没有显式进入 Goalspec，不得运行 `.goalspec/goalspec ...` 命令；普通问答、调试、小修或一次性工作默认不走框架。

## 权威链

- 意图只在 `.goalspec/active/goal.md`。
- intake package 只在 `.goalspec/active/intake-capture.md` 与 `.goalspec/active/constraint-suggestions.yaml`，`确认并应用 intake package` 前不能写入 `.goalspec/project/**`。
- Goal、Criteria、Constraints 只在 frozen `.goalspec/active/{goal,criteria,constraints}.yaml` 及其 hash 绑定中。
- 执行指令只在 `.goalspec/active/goal-driven-prompt.md`。
- 兼容契约只在 frozen `.goalspec/active/contract.yaml`。
- 事实只在 `.goalspec/active/evidence.yaml` 与 `.goalspec/active/trace.yaml`。
- Criteria 判定只在 `.goalspec/active/verdict.yaml`。
- 收口确认只在 `.goalspec/active/close-package.yaml` + `/goalspec close`，close package 必须显示 delivery mode。
- 长期记忆只在 `.goalspec/project/*.yaml`。
- 交付事实只在 `.goalspec/history/vNNNN/delivery.yaml`。

聊天、commit message、测试输出、Subagent 自述都不是完成判据。

## 耐久性优于精确

写 Goal、Criteria、Constraints、Prompt 及任何执行 brief 时，遵守耐久性优于精确：

- 禁文件路径和行号——它们会过期，让审批与证据频繁 stale。描述接口、行为、类型契约。
- 写行为，不写过程——写系统该做什么（what），不写怎么实现（how）。
- 清晰 Criteria + 显式出界——每个验收点可独立验证；显式写出“不做什么”，防镀金。

实现步骤、函数名、类名、表结构、施工顺序是实现细节，不是意图或约束，默认不进 `goal.md`/`contract.yaml`（除非人类明确确认为目标约束）。这条与 hash 绑定权威互为支撑：引用会过期的位置，等于制造无谓的 stale。

## Reopen 语义

`/goalspec reopen <reason>` 只用于 frozen Goal、Criteria、Constraints 本身错误、不足、矛盾、不可实现，或与人类新的验收口径发生冲突时。它不是“实现还没做完”的同义词，也不是“顺手加需求”的入口。

reopen 之后：
- 旧 frozen execution basis 立即失效；
- 你只能解释 reopen 原因、起草 Goal/Criteria/Constraints 修改建议、列出 blocking questions，并引导人类重新 review / approve / freeze；
- 不得继续修改业务代码、追加 verdict、生成或沿用 close package；
- 不得跳过 re-freeze 直接恢复 `/goalspec run`。

reopen 不等于“全部重做”。框架记录的是 Criteria/evidence/verdict 层的完成情况，不是任务清单。reopen 后应按受影响的 Criteria 做 impact analysis（`unchanged` / `modified` / `added` / `removed`）并重验受影响的 Criteria；只有 Goal/Constraints 的全局变化才应触发全量 re-validation。

若用户提出的新要求不会改变“当前 Goal 是否完成”的判断，而只是额外增量，优先 close 当前变更，再开启新的 `/goalspec start <intent>`，而不是 reopen 当前轮。

## Close Package 与收口

当所有 required Criteria 都有 fresh Master pass verdict 后，再次运行 `.goalspec/goalspec run` 会生成 close package 并进入 `ready_to_close`。close package 绑定 contract/evidence/verdict/memory-patch/changed-files/delivery 的 hash——任一改变即 stale，`/goalspec close` 会拒绝并要求重新生成。

用户输入 `/goalspec close` 表示确认当前 close package，并一次性授权：应用长期记忆、归档 history，并执行 `.goalspec/project/profile.yaml` 中配置的 delivery mode（`github_pr` / `push_only` / `local_commit` / `archive_only`）。close 是可恢复的：中途失败会停在 checkpoint，再次运行 `/goalspec close` 从断点续跑，不重复主 commit。

AI 不得绕过 close package hash 校验、final verification、scope-check 或 CLI checkpoint；close 失败时只报告 CLI 输出的 blocker 与 next user action。
