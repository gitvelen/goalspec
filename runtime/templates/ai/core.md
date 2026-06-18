# Goalspec — core rules

本项目使用 Goalspec 框架。开始任务前：

1. 运行或读取 `.goalspec/goalspec status`。
2. 按 `NEXT_USER_ACTION` 和冻结状态行动。
3. `/goalspec run` 前不得修改业务代码。
4. `/goalspec run` 允许后，必须完整读取 `.goalspec/active/goal-driven-prompt.md`，并将其中的 Goal、Criteria、Constraints 作为当前执行权威。
5. 不要自评完成。完成判定只能来自 Master/Guardian verdict 和 `goalspec complete`。

权威链：
- 意图只在 `.goalspec/active/goal.md`。
- intake package 只在 `.goalspec/active/intake-capture.md` 与 `.goalspec/active/constraint-suggestions.yaml`，确认前不能写入 `.goalspec/project/**`。
- Goal、Criteria、Constraints 只在 frozen `.goalspec/active/{goal,criteria,constraints}.yaml` 及其 hash 绑定中。
- 执行指令只在 `.goalspec/active/goal-driven-prompt.md`。
- 兼容契约只在 frozen `.goalspec/active/contract.yaml`。
- 事实只在 `.goalspec/active/evidence.yaml` 与 `.goalspec/active/trace.yaml`。
- 完成判定只在 `.goalspec/active/verdict.yaml` + `goalspec complete`。
- 长期记忆只在 `.goalspec/project/*.yaml`。

聊天、commit message、测试输出、executor 自述都不是完成判据。

## 耐久性优于精确

写 Goal、Criteria、Constraints、Prompt 及任何执行 brief 时，遵守耐久性优于精确：

- 禁文件路径和行号——它们会过期，让审批与证据频繁 stale。描述接口、行为、类型契约。
- 写行为，不写过程——写系统该做什么（what），不写怎么实现（how）。
- 清晰 Criteria + 显式出界——每个验收点可独立验证；显式写出“不做什么”，防镀金。

实现步骤、函数名、类名、表结构、施工顺序是实现细节，不是意图或约束，默认不进 `goal.md`/`contract.yaml`（除非人类明确确认为目标约束）。这条与 hash 绑定权威（见 `docs/adr/0002`）互为支撑：引用会过期的位置，等于制造无谓的 stale。
