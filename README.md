# Goalspec 使用说明

## 快速上手

三步：装框架 → 装 AI skill → 在项目里开始。

### 1. 安装框架

把本仓库目录加入 `PATH`（一次性），然后在目标项目初始化：

```bash
export PATH="/path/to/goalspec-repo:$PATH"   # 或写入 ~/.bashrc / ~/.zshrc
cd /path/to/project && git init              # 项目必须是 git repo
goalspec init                                # 在项目内创建 .goalspec/
```

不想加 PATH 也可直接用显式路径：`/path/to/goalspec-repo/goalspec init`。

### 2. 安装 AI skill（用 AI 工具驱动开发时需要）

skill 教会 AI 工具识别 `/goalspec ...` 命令并按 `status` 驱动流程。按你的 AI 工具安装：

```bash
goalspec install-ai codex     # 或 claude / lingma
```

然后重启或重新加载该 AI 工具使其发现 skill。

### 3. 在项目里开始

在 AI 工具中打开已安装的项目，先看状态：

```text
/goalspec status
```

之后用少量高层命令即可（AI 自动跑底层 `goalspec ...`）：

```text
/goalspec begin <意图>      # 开始会话录入（或：/goalspec source <文件/目录> 添加来源）
/goalspec end               # 结束录入，生成 intake package 待你确认
/goalspec next              # 推进到下一步（AI 按 status 的 NEXT_ACTION 执行）
```

`确认` 即批准 intake package 并应用约束建议；`complete` 是唯一的完成判定入口。

> 前置：`git` 可用，项目须是 git repo。`yq`（mikefarah v4）的获取按平台：**Windows 已内置** `runtime/bin/yq-windows-amd64.exe`，开箱即用；**Linux / macOS** 用系统 yq（如 `brew install yq`、包管理器，或 `goalspec yq install` 在线补齐）。系统已装的 `yq` 须为 **mikefarah v4**（kislyuk/jq 版不兼容），框架会优先复用。各步骤的机制与字段含义见下文。

## 框架特点

Goalspec 要解决的核心问题是：**"开发者或 AI 说完成了，但目标真的达成了吗？"** 它用一套可判定的机制，把"完成"从一个主观判断变成一个可复核的状态。下面是它的机制特点（非功能罗列，是设计层面"为什么这样"）。

- **目标驱动，而非任务驱动**：输入是人类的目标（意图），不是任务清单。框架把目标编译成 *criteria（完成判据）+ work units（行为切片）+ constraints*。开发围绕"目标是否达成"组织，而不是"任务是否勾完"。
- **criteria 是唯一的完成判据**：完成 ≠ 测试通过 ≠ 代码写完 ≠ "看起来能用"。只有所有 required criteria 被 evidence 证明、guardian 判 `pass`、`complete` 门通过才算完成。这直接杜绝"跑通几个测试就声称 done"。
- **四角色硬分离（利益冲突隔离）**：intake（承接意图）/ compiler（编译契约）/ executor（执行）/ guardian（独立判定）的读写边界严格分离。executor 不能改契约 / verdict / 项目记忆，不能自评完成；guardian 在 fresh context 只读 contract / evidence / trace，不读 executor 对话、不改代码。本质是：**执行者不能判定自己完成**。
- **权威链（authority chain）**：每类事实有唯一权威来源——意图只在 `goal.md`、契约只在 frozen `contract.yaml`、事实只在 `evidence.yaml` / `trace.yaml`、完成判定只在 `verdict.yaml` + `complete`、长期记忆只在 `project/`**。聊天记录、commit message、测试输出、executor 自述都不是完成判据。
- **hash 绑定的 staleness**：任何关键文件（goal / contract / evidence / memory-patch）一旦变化，会通过 sha256 hash 使依赖它的旧 review / approval / verdict / complete 依据变 stale 并阻断推进，无法用过期的批准或判定蒙混过关。
- **evidence ≠ verdict**：evidence 只记事实（命令、退出码、artifact、`runtime_boundary`、`provider_source`、`completion_level`），不含结论；verdict 由 guardian 在干净上下文独立判定。防止用"我跑了测试"冒充"目标达成"。
- **机制不变量是硬约束，不是建议**：authority chain / 角色分离 / freshness / WU 调度 / git-scope 是框架强制门，违反任一会被命令 / review / judge / complete 阻断。
- **行为型 work unit**：WU 按行为切片（如"禁用用户无法登录"）而非模块任务（如"改 AuthService"），判定聚焦可观察行为、与具体实现解耦。
- **自包含 + 纯 bash / git**：每个项目 `.goalspec/` 自包含，不引入 Python / Node 运行时依赖；git 是硬前提。`yq`（mikefarah v4）在 Windows 上随框架内置（`runtime/bin/yq-windows-amd64.exe`）；Linux/macOS 走系统 yq 或 `goalspec yq install`。
- **`complete` 是唯一完成入口**：多重前置门——frozen contract、全部 required / final criteria 与 hard constraints 最新 verdict 为 pass、无 blocking question、scope-check pass、memory-patch 经 human approval、所有业务 changed files 归属到 passed WU，缺一不可。

## 适用项目

**适合：**

- AI agent 协作的开发项目——尤其需要防止 agent 自评完成、需要可审计的产出链路。
- 需要明确"目标达成"判据、且能被独立复核的开发。
- 行为可机器判定的功能开发（具备自动化验证路径：单元 / 集成测试、API、浏览器自动化等）。
- 需要长期沉淀项目能力 / 决策 / 防回归的项目——`complete` 时会把 capability / decision / regression 写入 `project/` 长期记忆，并在后续 contract 中自动注入 locked regression。

**不适合：**

- 纯探索 / 研究类工作——没有明确完成态、无法定义可判定的 criteria。
- 快速原型 / hackathon——v1 强制完整 lifecycle（review / approve / freeze / judge / complete），机制开销大于收益。
- 行为无法客观判定的纯主观 / 创意任务。
- 需要 v1 尚未支持的能力：UI dashboard、并行 work units、自动多 agent runner、自动 commit / push。

---

Goalspec 是一个项目内自包含的目标驱动开发框架。安装后，每个项目根目录会有自己的 `.goalspec/`，其中保存当前 goal、contract、evidence、verdict、history 和项目长期记忆。

核心原则：

- `.goalspec/active/goal.md` 是人类意图权威。
- `.goalspec/active/contract.yaml` 是冻结后的执行契约。
- `.goalspec/active/evidence.yaml` / `trace.yaml` 是事实记录。
- `.goalspec/active/verdict.yaml` + `goalspec complete` 是唯一完成判定。
- AI 工具插件、skills、slash commands 只是入口适配层；权威状态仍在项目内 `.goalspec/`。

## 1. 前置条件

目标项目必须是 git repo。`git` 须可用。`yq`（mikefarah v4）按平台获取：

```bash
git --version
# Windows：框架已内置 yq（runtime/bin/yq-windows-amd64.exe），无需任何操作。
# Linux / macOS：装系统 yq（如 `brew install yq`），或运行 `goalspec yq install` 在线补齐。
# 若系统已装 yq，须为 mikefarah v4（kislyuk 版不兼容）：`yq --version` 应含 "version v4..."。
```

如果目标项目还不是 git repo：

```bash
cd /path/to/project
git init
```

## 2. 安装到具体项目

推荐先一次性把本框架仓库目录加入 `PATH`（之后所有项目都用 `goalspec` 调用）：

```bash
# 例如框架克隆在 ~/goalspec
export PATH="$HOME/goalspec:$PATH"   # 或写入 ~/.bashrc / ~/.zshrc 持久化
```

然后进入目标项目初始化：

```bash
cd /path/to/project
goalspec init
```

或在任意目录用 `goalspec install <path>` 直接定向到某个项目（无需 cd）：

```bash
goalspec install /path/to/project
```

若不想加 PATH，也可直接用框架入口的显式路径（`goalspec` 可执行文件就在本仓库根目录）：

```bash
/path/to/goalspec-repo/goalspec init /path/to/project
```

安装后目标项目会新增：

```text
.goalspec/
  goalspec
  runtime/
  ai/
  skills/
  active/
  project/
  history/
  artifacts/
AGENTS.md      # 安装/更新 Goalspec 管理块，保留原有自定义内容
CLAUDE.md      # 安装/更新 Goalspec 管理块，保留原有自定义内容
```

验证：

```bash
cd /path/to/project
.goalspec/goalspec status
```

如果看到 `STATE`、`NEXT_ACTION`、`ROLE`、`READ`、`MAY_EDIT`、`MUST_NOT_EDIT` 等字段，说明安装成功。

## 3. 更新已安装项目中的框架

对已安装项目仍然使用 `goalspec init`（或 `goalspec install <path>`）。

```bash
cd /path/to/project
goalspec init
```

看到更新提示后输入 `y`：

```text
goalspec init: /path/to/project/.goalspec already exists. Update framework code and role templates while preserving project state? [y/N] y
```

更新会替换框架代码和角色模板，保留项目状态：

- 替换：`.goalspec/runtime/`、`.goalspec/ai/`、`.goalspec/skills/`、`.goalspec/goalspec`
- 保留：`.goalspec/active/**`、`.goalspec/project/**`、`.goalspec/history/**`、`.goalspec/artifacts/**`
- 自动补齐新版 active 文件和 state 字段
- 更新 `AGENTS.md` / `CLAUDE.md` 中 `<!-- GOALSPEC:BEGIN -->` 到 `<!-- GOALSPEC:END -->` 的 Goalspec 管理块；旧版 Goalspec 生成文件会替换为新版，自定义内容会保留

更新后验证：

```bash
cd /path/to/project
.goalspec/goalspec help
.goalspec/goalspec status
```

`help` 中应包含：

```text
intake begin [text]
intake add-source <path>
intake end
intake apply-suggestions
new-goal [--source <path>] [text]
approve ... intake-package ...
```

## 4. 在 AI 工具中安装为插件或技能

Goalspec 的 AI 安装不是所有工具一个目录。按你使用的 AI 工具选择：

```bash
goalspec install-ai codex
goalspec install-ai claude
goalspec install-ai lingma
```

安装结果：

```text
Codex:
  ~/.codex/skills/goalspec/
  ~/plugins/goalspec/
  ~/.agents/plugins/marketplace.json

Claude:
  ~/.claude/skills/goalspec/
  ~/.claude/plugins/goalspec-local/

Lingma:
  ~/.lingma/skills/goalspec/
  ~/.lingma/commands/goalspec.md
```

只安装裸 skill 时可以使用兼容命令：

```bash
goalspec install-skill /custom/skills/goalspec
```

安装后重启或重新加载 AI 工具。skill/plugin 的作用是教会 AI 工具：

- 如何识别 `/goalspec ...` 用户命令。
- 如何读取 `.goalspec/goalspec status`。
- 如何在 `/goalspec end` 后生成 `intake-capture.md` 和 `constraint-suggestions.yaml`。
- 如何把用户确认翻译成底层审批和应用命令。

说明：skill 只负责让 AI 工具知道如何使用 Goalspec；项目权威状态仍在项目内 `.goalspec/`。

## 5. 如何开始一次 Goalspec 开发

安装 AI adapter 后，在 AI 工具里使用少量高层命令即可；AI 负责运行底层 `.goalspec/goalspec ...`。

打开项目后可以先说：

```text
/goalspec status
```

或直接让 AI 检查：

```text
检查 Goalspec 状态
```

### 5.1 会话录入变更意图

适合需求还在多轮聊天中逐步说明的情况。

开始录入：

```text
/goalspec begin 给 TTS 生成结果加缓存
```

或者：

```text
开始录入 Goalspec 变更意图：给 TTS 生成结果加缓存。
```

然后按正常聊天补充意图、边界、约束、风险、文档路径等。AI 会把正式意图记录到 `intake-conversation.md`，不会直接写最终 `goal.md`。

结束录入：

```text
/goalspec end
```

AI 会整理 `intake-capture.md` 并展示给你确认。

同时，AI 会生成：

```text
.goalspec/active/constraint-suggestions.yaml
```

里面区分：

- 本次 goal 约束：确认后写入 `goal.md` 第 6 节。
- 长期项目事实：确认后合入 `project/profile.yaml`。
- 长期项目约束：确认后合入 `project/constraints.yaml`。
- 不确定项：进入 `open_questions`，需要你确认。

你只需要回复：

```text
确认
```

或者直接告诉 AI 修改建议稿。确认后，AI 会批准 intake package、应用约束建议、继续写高保真 `goal.md`，再进入 review / approval / compile / freeze 流程。

### 5.2 从文件或目录开始

适合已经有需求文档、会议纪要、plan 文档或目录材料。

文件来源：

```text
/goalspec begin 基于需求文档启动变更
/goalspec source docs/spec.md
/goalspec end
```

目录来源：

```text
/goalspec begin 基于需求目录启动变更
/goalspec source docs/requirements
/goalspec end
```

或者直接说：

```text
基于 docs/spec.md 开始一个 Goalspec 变更。
```

AI 会登记 source、保存 snapshot/hash 或目录清单，然后读取材料，生成 intake package 和约束建议，经你确认后再写 `goal.md`。

### 5.3 继续推进

后续正常说：

```text
/goalspec next
```

AI 每次都会先看：

```text
STATE
NEXT_ACTION
ROLE
MAY_EDIT / MUST_NOT_EDIT
```

底层 review、approve、compile、freeze、judge、complete 仍然存在，但普通使用中由 AI 按 `status` 自动调用。用户只需要确认关键产物。

`complete` 是唯一完成入口。测试通过、AI 自述“完成”、executor evidence 里写“已通过”都不能替代 `complete`。

## 6. 常见问题

### AI 能自动读取 begin/end 之间的聊天吗？

不能。Goalspec CLI 是 bash/yq/git 框架，读不到 Claude/Codex/Lingma 的私有会话历史。

会话录入依赖 AI intake agent 在 collecting 状态下主动写：

```text
.goalspec/active/intake-conversation.md
```

这就是为什么会话来源必须先生成并批准：

```text
.goalspec/active/intake-capture.md
.goalspec/active/constraint-suggestions.yaml
```

确认后，AI 才会运行底层 `approve intake-package` 和 `intake apply-suggestions`。

### 为什么不直接把整篇文档塞进 goal.md？

`goal.md` 是权威目标语义文档，不是原文仓库。大段原文会混入背景、实现建议、未确认假设和噪声。

正确做法：

- 原始材料进入 source snapshot。
- AI 高保真结构化承接语义到 `goal.md`。
- AI 把约束候选放入 `constraint-suggestions.yaml`，经确认后再落入 `goal.md` 或 `project/**`。
- 关键不确定项进入 `questions.yaml`。

### 什么时候需要 reopen？

如果执行过程中发现目标、criteria、scope、证据要求本身有问题，不要硬做。使用：

```bash
.goalspec/goalspec reopen "reason"
```

然后重新修正 goal/contract，并重新 review/approve/freeze。

### 已安装项目如何确认框架是新版？

```bash
.goalspec/goalspec help | grep -E 'intake begin|intake add-source|intake end|apply-suggestions|intake-package'
```

能看到这些入口，说明至少包含 Intake Package 和约束建议流程。
