<!-- GOALSPEC:BEGIN -->
# Goalspec

本项目使用 Goalspec Goal-Driven Prompt 框架。项目内 `.goalspec/` 是唯一权威；本文件只是 agent 入口说明。

## 每次开始

1. 先运行或读取 `.goalspec/goalspec status`。
2. 按 status 输出的 `STATE`、`GOAL`、`FROZEN`、`PROMPT_READY`、`RUN_ALLOWED`、`NEEDS_HUMAN_CONFIRMATION`、`BLOCKERS`、`UNMET_CRITERIA`、`NEXT_USER_ACTION` 行动。
3. 如需角色细节，读取 `.goalspec/ai/core.md` 和对应角色文件。
4. 不要从闲聊自动创建 goal。只有在人类明确要求开始 Goalspec 变更、录入、或基于某个来源启动时，才进入 intake。

## 用户入口

- `.goalspec/goalspec start "<意图>"` 开启正式 intake 窗口。
- `.goalspec/goalspec source <path>` 添加材料。
- `.goalspec/goalspec end` 关闭 intake，并起草 Goal、Criteria、Constraints、out-of-scope、blocking questions 供人类确认。
- 人类确认只冻结产物并生成 `.goalspec/active/goal-driven-prompt.md`，不开始实施。
- `.goalspec/goalspec run` 是唯一实施入口。

## Intake Package 硬规则

会话、文件、目录来源结束后，先生成并展示：

- `.goalspec/active/intake-capture.md`
- `.goalspec/active/constraint-suggestions.yaml`

人类确认后，运行：

```bash
.goalspec/goalspec approve intake-package
.goalspec/goalspec intake apply-suggestions
```

确认前不要写 `.goalspec/project/**`，不要把未确认的实现步骤、文件名、函数名、表结构当作目标约束。

## Run 硬规则

收到 `/goalspec run` 后：

1. 运行 `.goalspec/goalspec run`。
2. 如果输出 `GOALSPEC_RUN_ALLOWED: false`，立即停止。
3. 如果输出 `GOALSPEC_RUN_ALLOWED: true`，在修改任何业务代码前完整读取 `.goalspec/active/goal-driven-prompt.md`。
4. 将 Prompt 中的 Goal、Criteria、Constraints 视为当前执行的权威控制指令。
5. 不得用自己的任务计划替代该 Prompt，不得凭记忆执行。
6. 不得把“确认”或“继续”视为 run 许可，除非用户明确输入 `/goalspec run`。

如果工具支持显式 subagents，创建且只创建一个 Subagent 执行；否则用可见的 `Master Evaluation`、`Subagent Work`、`Evidence/Progress Report` 阶段模拟角色分离。

## 完成规则

不要自评完成。测试通过、Subagent 自述、evidence 记录都不是完成判定。

完成只能来自 Master/Guardian 基于 evidence 对 Criteria 的 pass verdict，以及 `.goalspec/goalspec complete` 成功通过完成门。

<!-- GOALSPEC:END -->
