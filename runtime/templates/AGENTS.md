<!-- GOALSPEC:BEGIN -->
# Goalspec

> 快速判定：本块仅在人类发出 `/goalspec ...` 或明确要求一次正式 Goalspec 受管变更时生效；普通问答、调试、小修请忽略本块，按项目常规开发处理。

本项目使用 Goalspec。项目本地 `.goalspec/` 目录是真相源；本受管块只是 Goalspec 受管工作的薄操作指南。

## 范围与优先

Goalspec 是显式 opt-in。只有当人类显式使用 `/goalspec ...`，或清楚要求执行一次正式的 Goalspec 受管变更时，才进入该生命周期。否则按普通开发工作处理：遵循项目常规指导、不运行 `.goalspec/goalspec ...`、不得把普通请求擅自升级为 Goalspec 生命周期。

当请求属于 Goalspec 受管时，门禁以本块为准。详细角色规则读 `.goalspec/ai/core.md`，勿凭记忆执行。

## 开始

Goalspec 受管工作前，运行或读取：

```bash
.goalspec/goalspec status
```

按 `STATE`、`FROZEN`、`PROMPT_READY`、`RUN_ALLOWED`、`CLOSE_READY`、`NEEDS_HUMAN_CONFIRMATION`、`BLOCKERS`、`UNMET_CRITERIA`，尤其 `NEXT_USER_ACTION` 行动。

只有 `closed` 表示本次变更已完整收口，才可开启下一次 `/goalspec start <intent>`。

`/goalspec start` 还要求业务 worktree 相对 `HEAD` 干净：dirty 的改动会在 `source` 时被快照进 intake provenance，而该快照在 `freeze` 之前就已冻结，freeze 无法捕获。启动前先 commit 或 stash 业务改动。

## 人类命令映射

人类命令被机械翻译为 Agent CLI 调用，且仅允许下表中匹配的人类输入触发对应翻译。

| 人类命令 | Agent CLI 翻译 | 停止点 |
| --- | --- | --- |
| `/goalspec status` | `.goalspec/goalspec status` | 报告状态与 `NEXT_USER_ACTION`。 |
| `/goalspec start <intent>` | 先运行 status，再仅从 `no_goal` 或 `closed` 执行 `.goalspec/goalspec start "<intent>"`。 | intake 已开启；勿实施。 |
| `/goalspec source <path>` | `.goalspec/goalspec source <path>` | source 已添加；勿关闭 intake。 |
| `/goalspec end` | `.goalspec/goalspec end` | 起草并展示 review package；等阶段化确认。 |
| `确认并应用 intake package` | 先 `.goalspec/goalspec review prompt intake-capture`（hot-context，读对话核对 capture 覆盖度+provenance）并 `review apply` 通过；再 `.goalspec/goalspec approve intake-package`（硬门禁：无 passing intake-capture review 则拒绝）、`.goalspec/goalspec intake apply-suggestions` | 应用已确认的建议后停止。 |
| `确认并冻结契约` | 仅运行 status 所要求的 review、approve、freeze 命令（针对已 review 的 Goal/Criteria/Constraints）。 | 生成 `.goalspec/active/goal-driven-prompt.md` 后停止；勿实施。 |
| `/goalspec run` | `.goalspec/goalspec run` | 若允许，读取 prompt 后进入 Master/Subagent 自主 loop，直到所有 required Criteria 拿到 fresh Master pass、或触发 stop condition；全 pass 后再次 run 生成 close package 并停止。 |
| `/goalspec close` | `.goalspec/goalspec close` | 报告成功或 CLI blocker；绝不手动替代 close。 |
| `/goalspec reopen <reason>` | `.goalspec/goalspec reopen <reason>` | 起草影响与修订后的契约材料；等重新 review 与重新 freeze。 |

## 人类门禁

`start`、`end`、`run`、`close` 是人类门禁：仅当人类发出对应的 `/goalspec` 斜杠命令时，才执行匹配的 `.goalspec/goalspec <cmd>`，绝不自启。细则（不得因意图已采集自跑 `goalspec intake end`、不得因 Criteria 看似可满足自跑 `run`、不得因 close package 已存在自跑 `close`、裸"确认/继续/ok/沉默"不算授权）见 `.goalspec/ai/core.md`。

## Intake 与 Freeze

intake 期间：专注澄清（只问 Goal/Criteria/Constraints/scope/risk/用户可见行为相关问题）、添加已批准 source；不要手动记录会话——`active/intake-conversation.md` 由 `goalspec intake end` 从 session transcript 自动切片生成。不得冻结工件、生成 Goal-Driven Prompt、修改业务代码、或自行判定 intake 已结束。

`/goalspec end` 后：从 `.goalspec/active/intake-conversation.md`、`.goalspec/active/intake-sources.yaml`、已批准 source 快照、`.goalspec/active/intake-capture.md`、`.goalspec/active/constraint-suggestions.yaml` 生成并展示精简 review package（七项明细见 `.goalspec/ai/intake.md`），等阶段化确认。

`approve intake-package` 前必须先有一条 passing 的 **intake-capture review**（`goalspec review prompt intake-capture` → `review apply`）。这是唯一读对话核对 capture 是否覆盖用户意图的门禁（intake/contract review 是 fresh-context 形式审查，故意不读对话）。capture 改动后该 review 失效，需重跑。

写 `.goalspec/project/**` 前需 `确认并应用 intake package`；冻结已 review 的 Goal/Criteria/Constraints 前需 `确认并冻结契约`。确认永远不等于开始实施。

## Criteria 审查最低要求

展示给人类的每条 required Criterion 需含：

- `failure means incomplete`：为何未通过此项意味着 Goal 未完成。
- `observable result`：Master 可检查的行为或状态。
- `evidence path`：能证明它的 evidence 要求或运行时边界。

保持 required Criteria 清晰、可据证据判断、与 Goal 相关、最小化。nice-to-have 移入 `optional_criteria`；执行边界移入 Constraints。起草方法论（产品覆盖 / 工程有效性 / 测试覆盖 / 可验收性 四视角，主线为覆盖 goal.md 所有目标分支）见 goalspec skill 的 `references/criteria-writing.md`；角色细则见 `.goalspec/ai/compiler.md`。

## Run / Reopen / Close

当显式要求 `/goalspec run` 时，运行 `.goalspec/goalspec run`。若打印 `GOALSPEC_RUN_ALLOWED: false`，停下并报告 blocker；若允许，修改业务代码前完整读取 `.goalspec/active/goal-driven-prompt.md`，再按其 Master/Subagent loop 自主推进：Master 对未通过的 required Criteria 驱动 Primary Subagent（可委派 bounded Worker Subagents）收集 evidence；Master 从 fresh evidence 经 `.goalspec/goalspec judge apply` 路径判定每条 Criteria（让 iteration/cap/stalled 计数生效）；未全 pass 且仍能进展时继续该循环，不得因一次 attempt 完成、失败或自述完成就宣布成功。

Subagent 可产出 evidence，但不得宣布最终成功；仅 `evaluated_by: master` 的 verdict 可判定 Criteria。测试通过、Subagent 自述、evidence 文本都不构成收口。

run-loop（即上述 Master/Subagent 循环）在以下 stop condition 任一成立时停下，并报告 status 的 `NEXT_USER_ACTION`，勿盲目重试：所有 required Criteria 拿到 fresh Master pass（loop 目的达成，停止实施）；iteration 触顶被 `capped`（上限见 `profile.run_loop.max_iterations`，需 `/goalspec close` 或 `/goalspec reopen` 重置）；`stalled`（默认连续 3 轮无 verdict/evidence 进展，疑似 spec 缺陷，需 `/goalspec reopen`）；judgment 类 Criteria 阻塞（需人类/Master 裁决，非 Subagent 重试）；或 stale/缺失 prompt。

reopen 仅用于冻结的 Goal/Criteria/Constraints 本身错误、不足、矛盾、或与人类新的验收口径冲突；细则见 `.goalspec/ai/core.md`。

close 仅在人类运行 `/goalspec close` 后经 `.goalspec/goalspec close` 完成，不得用 git、push、PR、归档、状态编辑或直接写 `status: closed` 替代。收口需所有 required Criteria 拿到 fresh Master pass verdict、close-readiness 在 `/goalspec run` 中通过、当前 close package、最终验证、验证后 changed-files 复核、密钥/大文件扫描、（若配置）smoke 门禁、以及已配置的 delivery mode。
<!-- GOALSPEC:END -->
