# Goalspec — core rules

本项目使用 Goalspec 框架。开始任务前：

1. 运行或读取 `.goalspec/goalspec status`。
2. 按 `NEXT_ACTION` 加载对应角色指令文件（`.goalspec/ai/{intake,compiler,executor,guardian}.md`）。
3. 严格遵守 `ROLE` / `READ` / `MAY_EDIT` / `MUST_NOT_EDIT` 边界。
4. 不要自评完成。完成判定只能来自 fresh-context guardian verdict 和 `goalspec complete`。

权威链：
- 意图只在 `.goalspec/active/goal.md`。
- 契约只在 frozen `.goalspec/active/contract.yaml`。
- 事实只在 `.goalspec/active/evidence.yaml` 与 `.goalspec/active/trace.yaml`。
- 完成判定只在 `.goalspec/active/verdict.yaml` + `goalspec complete`。
- 长期记忆只在 `.goalspec/project/*.yaml`。

聊天、commit message、测试输出、executor 自述都不是完成判据。
