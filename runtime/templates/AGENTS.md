# Goalspec

本项目使用 Goalspec 框架管理目标驱动的开发。

开始任务前运行或读取 `.goalspec/goalspec status`，按 `NEXT_ACTION` 加载对应角色指令。
只有在人类明确授权开始项目变更时，才创建 active goal：
- 会话录入：`.goalspec/goalspec intake begin [意图]`，人类结束后 `.goalspec/goalspec intake end`。
- 文件/目录来源：`.goalspec/goalspec new-goal --source <path> [意图]` 或 `.goalspec/goalspec intake add-source <path>`。
会话/文件来源录入结束后，先写 `active/intake-capture.md` 与 `active/constraint-suggestions.yaml`，取得人类确认并运行 `goalspec approve intake-package && goalspec intake apply-suggestions`，再写 `active/goal.md`。
不要自评完成。完成判定只能来自 fresh-context guardian verdict 和 `goalspec complete`。
