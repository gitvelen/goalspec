<!-- GOALSPEC:BEGIN -->
# Goalspec

本项目使用 Goalspec 框架管理目标驱动的开发。项目内 `.goalspec/` 是唯一权威；本文件只是 agent 入口说明。

## 每次开始

1. 先运行或读取：
   `.goalspec/goalspec status`
2. 严格按 status 输出的 `NEXT_ACTION`、`ROLE`、`READ`、`MAY_EDIT`、`MUST_NOT_EDIT`、`BLOCKERS`、`CURRENT_WORK_UNIT` 行动。
3. 当 status 要求某个角色时，读取 `.goalspec/ai/core.md` 和对应角色文件：
   `.goalspec/ai/intake.md`、`.goalspec/ai/compiler.md`、`.goalspec/ai/executor.md`、`.goalspec/ai/guardian.md`。
4. 不要从闲聊自动创建 goal。只有在人类明确要求开始 Goalspec 变更、录入、或基于某个来源启动时，才进入 intake。

## 常用入口

- 会话录入：`.goalspec/goalspec intake begin "<意图>"`，结束时运行 `.goalspec/goalspec intake end`。
- 添加材料：`.goalspec/goalspec intake add-source <path>`。
- 快捷创建：`.goalspec/goalspec new-goal --source <path> "<意图>"` 只用于明确要求从来源快速建立 active goal；之后仍必须按 status 补齐 intake package。
- 继续推进：先运行 `.goalspec/goalspec status`，只执行当前 `NEXT_ACTION`。

## Intake Package 硬规则

会话、文件、目录来源结束后，先生成并展示这两个文件给人类确认：

- `.goalspec/active/intake-capture.md`
- `.goalspec/active/constraint-suggestions.yaml`

人类确认后，运行：

```bash
.goalspec/goalspec approve intake-package
.goalspec/goalspec intake apply-suggestions
```

然后才可以写 `.goalspec/active/goal.md`。确认前不要写 `.goalspec/project/**`，不要把未确认的实现步骤、文件名、函数名、表结构当作目标约束。

## 角色边界

- intake：只承接意图、来源、约束候选和 `goal.md`；不写业务代码、contract、verdict。
- compiler：把批准后的 `goal.md` 编译为 draft contract；不写业务代码。
- executor：只在 contract 允许的路径内实现，并写 factual evidence；不改 goal、contract、verdict、project memory。
- guardian：fresh-context 判定 evidence 是否满足 contract；不改业务代码。

## 完成规则

不要自评完成。测试通过、executor 自述、evidence 记录都不是完成判定。

完成只能来自：

1. guardian 基于 fresh context 写出通过的 verdict；
2. `.goalspec/goalspec complete` 成功通过完成门。

<!-- GOALSPEC:END -->
