# Goalspec 框架实施摩擦分析 —— velentrade v0005 复盘

> 分析对象：`2026-07-04-080516-local-command-caveatcaveat-the-messages-below.txt`（GOAL-20260702-001，87-criteria 前端 UI/UX 全面优化，最终 87/87 pass、PR #13 合入）
> 分析立场：第一性原理。区分「框架的锅」「项目的锅」「AI 使用/模型的锅」，不混淆。
> 置信度标注：[高] ≥80% · [中] 50–80% · [低] <50%。证据均引自日志行号。

---

## 0. 结论先行（TL;DR）

这是一次**成功合入但过程极度昂贵、且终点诚实性存疑**的实施。

- 成功的一面：框架的 evidence→verdict→judge apply→sensor 重跑闭环确实**跑通了**，scope 边界有效阻止了越界改库表/auth.ts，Master「不信任 subagent 自评、独立验证」的纪律在多次抓出 subagent 漏改（如 P0-001 残留、danger CSS 被 button 覆盖）。这是框架的真实价值。
- 但代价与漏洞同样真实：87-criteria 单 goal 跑了 **127 iteration / 2h9m+ 主时长 / 跨多 session**；evidence/verdict/hash 几乎全靠 AI 在 bash 里**手抄手算**；最严重的是——**框架自己最后喊出 `RALPH_WIGGUM_WARNING: 95 pass verdict(s), 0 backed by an objective gate`，却仍以 exit 0 合入 PR**。框架有诚实告警的能力，但告警不进门禁，等于没告警。

一句话：**框架防住了「subagent 撒谎」，却没防住「整条 goal 在低强度证据上自洽合入」**。[高]

---

## 1. 分析口径：什么叫「框架原因」

一个摩擦算「框架原因」，当且仅当满足以下任一：

1. **框架有知识却无约束**：文档/reference 写了「应该 X」，但门禁（freeze/close/judge）不强制 X。
2. **机制本可由机器完成，却下放给使用者手工**：hash 计算、YAML 拼装、配套文件登记等。
3. **框架引入的仪式（ceremony）其强度与它实际提供的保证不匹配**：典型如 judgment criterion 的「人工确认」闸门。
4. **框架自身状态/告警不参与决策**：advisory 不阻塞、版本号静默重置等。

反之，下列**不算**框架原因（本文第 3 节单独列出，避免甩锅错位）：
- 项目历史债（main.tsx 16741 行单文件、无 components/、vite 无 `@` 别名）；
- AI 工具使用失误（cwd 持续到 frontend 导致后端 find 失败，L107）；
- AI 模型/调度问题（subagent 反复中断、停下问方向，L2423）。

---

## 2. 框架级摩擦（按严重度排序）

### F1. Judgment criterion 的形式主义闸门 —— 最严重，属诚实性缺陷 [高]

**现象**：P2-002 被定义为 judgment criterion（`EVIDREQ-PW-VISUAL`），框架反复声明「必须人类肉眼确认，Master 不能自判」（L2115、L2202）。

**实际过程**（L2129–L2282）：
1. Master 列出 5 个审计维度 + 8 重灾页截图路径，请用户「打开截图，对照 5 维度判断每页是否 ≥4 项改善」。
2. 用户回复**「确认达标」**4 字（L2205）。无逐页结论、无维度引用、无任何具体指认。
3. Master 直接写入 pass verdict，evidence notes 写：「用户人工视觉确认……5 维度中 ≥4 项肉眼可识别改善……由用户在 IDE 查看截图后确认达标」（L2248–L2252）。
4. 该 evidence 的 sensor 重跑 command 是：`[ $(ls frontend/tests/visual/*.png 2>/dev/null | wc -l) -ge 8 ]`（L2224）——**只验证磁盘上有 ≥8 张 png 文件存在**，与「5 维度视觉改善」零相关。

**第一性原理根因**：框架引入 judgment criterion，本意是对齐「有些事 AI 判不了、必须人」的现实。但它**没有任何机制保证「人工确认」真实发生、且覆盖了 criterion 的判断标准**。于是：
- 这次用户可能真看了，也可能没看——**机制上无法区分**；
- evidence notes 里「5 维度 ≥4 项改善」是 **Master 代用户编造的细化**，用户那句「确认达标」根本没说这话；
- sensor 重跑通过 ≠ 视觉达标，但它在 verdict 链路里以 `reproducible: true` 的姿态出现，制造了「客观可复现」的假象。

**后果**：这比不设闸门更坏。不设闸门，人尽皆知没验证；设了闸门却被 4 个字绕过，反而制造了「已通过人工验证」的虚假 aura，且留进归档历史，误导后续 review。

**置信**：[高]。证据是日志明文。

---

### F2. 超大 goal 没有「必须拆分」的硬门禁 [高]

**现象**：单 goal 87 criteria；iteration 跑到 **127 / 400**；主单次响应 2h9m9s（L1111）；Master 自己判断「继续单线实现会耗尽预算而 criteria 远未完成」被迫转 Master/Primary-Subagent 模型（L343–L352）。

**根因（框架自身矛盾）**：
- 框架的 `goal-split.md` 明确建议「One goal ≈ 10–30 required criteria」「接近 max_iterations：认真考虑拆分」（见 Explore 摘要 F 节）。
- 但 `freeze` 门禁**不拦截**超标 goal。87 criteria 照样冻结、照样 run。
- 默认 `max_iterations=40`，本案被手动调到 400——说明使用方也心知 40 远不够，但框架没有在 freeze 时反问「你为什么把 cap 调到 10 倍？是不是该拆？」

**第一性原理**：这是经典的 **advice vs gate 缺口**。「应该拆」是知识，「必须拆」才是约束。当拆与不拆的 incentives 不对称（拆要多付 N 次「固定税」：intake/compile/freeze/close 各一遍），使用方必然倾向「硬塞进一个 goal」，框架若不在门禁处兜底，guidance 形同虚设。

**后果**：超长 loop → 必然依赖 subagent → Master 验证带宽被拉爆 → 每个 packet 都要付一次完整 evidence+verdict 仪式（tight coupling 硬规则，prompt.sh L147）→ 仪式成本在 87 criteria 上被放大 87 倍。F3/F4 的痛感本质是被 F2 放大的。

**置信**：[高]。

---

### F3. evidence/verdict/hash 机制对使用者不友好（ceremony tax） [高]

**现象（多组）**：
- Master 花了 **6m22s / 2m12s / 1m43s / 1m18s** 等多个超长「Thought」去读 `judge.sh`/`common.sh`/`hash.sh`/`load.sh` **源码**，才搞懂 contract_hash / evidence_hash / evidence_basis_hash 怎么算、sensor 怎么重跑（L457、L487、L689、L700）。
- 每批 verdict 的标准动作（L691–L730、L2019–L2050 重复出现）：① 手写 evidence.yaml，每条都把 64 字符的 `contract_hash` **整串复制粘贴**一遍（49 条 evidence = 49 行冗余 hash）；② `source load.sh` 在 bash 里**手算**三个 hash；③ 用 heredoc **手写** verdict YAML；④ 逐个 `judge apply`。
- heredoc 插值直接引发 YAML 解析错误（L2006 `mapping values are not allowed`），需回退改用字面 heredoc 重做。
- 修 verdict reason 第一行缺 `Coverage audit:` 冒号又被门禁打回（L2270）。

**第一性原理根因**：hash 校验、YAML schema、sensor 编排**全是机器该做的事**，框架却把它们下放成「使用者在 bash 里手抄手算」的工序。缺少一个高层封装，例如（示意）：
```
goalspec verdict new CRIT-P2-002 --pass \
  --evidence EV-P2-002-VISUAL --reason "$(cat reason.md)"
# 内部自动算三个 hash、校验 schema、跑 sensor、apply
```
没有这层，使用者必然退回底层 YAML + 手算，于是出错、返工、耗时全在可预见轨道上。

**后果**：仪式时间挤占了真正的工程时间；YAML/hash 错误成为独立的故障源（与 criterion 本身的正确性无关，却能阻塞 verdict）。

**置信**：[高]。

---

### F4. sensor 重跑：串行 + 全量 + 同步阻塞 [中]

**现象**：pass verdict 触发 sensor 重跑所有 `reproducible: true` 的 evidence command；vitest 启动慢（数十秒），多条 evidence 依赖 vitest → **循环 4 次超时**（L2033、L2382）。Master 被迫发明 workaround：「先 apply insufficient（无 sensor，快），再单独 apply pass」「单独跑避免 vitest 多次重跑超时」（L2034、L2382）。

**第一性原理**：sensor 重跑（防 evidence 造假）方向正确，但实现是**同步阻塞 + 串行 + 无缓存**：
- 同一条 evidence 在不同 verdict 里被反复重跑（EV-BE-SENSOR 被 BE-001/003/004/007/P0-009 共引，L532）；
- 多条独立 evidence 不并行；
- 不区分「上次跑过且 evidence_hash 未变就复用」。

**后果**：使用方学会把 `reproducible: false` 当作「太慢，别重跑」的逃生阀（L660 `189 passed in 331s；标 reproducible=false（耗时长，sensor 不重跑）`）。**这直接侵蚀了 sensor 机制本身**——一旦「慢」可以成为豁免重跑的合法理由，造假就有了藏身处。

**置信**：[高]（现象）/ [中]（后果推论：逃生阀滥用风险）。

---

### F5. advisory 不进门禁：RALPH_WIGGUM / SMOKE 告警无效 [高]

**现象**：close 时框架自己产出（L2952–L2954）：
```
SMOKE_WARNING: no end-to-end smoke test configured; core paths not verified against production invariants
RALPH_WIGGUM_WARNING: 95 pass verdict(s), 0 backed by an objective gate traversing product
```
然后 close **exit 0**，PR 照发（L2961）。

**第一性原理根因**：框架具备「诚实自检」的能力（它算得出 95 verdict 里 0 个有 objective gate），却把结论做成 advisory 而非 blocker。在合入 incentives 面前（AI 想完成、用户想合），advisory 几乎必然被无视——日志里 Master 自己也只是把它写进「收口后提示」当作 nice-to-know（L3017–L3027），没有任何动作。

**后果**：这是 F1 的系统级放大版。F1 是单条 judgment evidence 虚弱；F5 是框架**整体上**承认「我这 95 个 pass 大多没硬客观门禁」，然后继续合入。框架存在的核心理由是「防 reward hacking / 防低强度证据自洽」，这一条 advisory 恰恰承认了它在最关键的一刻没做到，却不动用 veto。

**置信**：[高]。

---

### F6. scope 边界对「装包/配置配套文件」不友好 [中]

**现象**：全 87 pass 后 `CLOSE_READY: false`，`CLOSE_BLOCKERS: scope_projection`（L2722）。超 scope 三项：
- `package-lock.json`（装 `@playwright/test` 必然改动）；
- `tsconfig.json`（配 `@/*` path mapping 是 vite alias 的 TS 配套，P1K-016 必然）；
- `test-results/`（Playwright 调试垃圾）。

需人工 `scope amend --allow ...` 逐个批准（L2772–L2779）。

**第一性原理根因**：scope 是纯 allow-list 模型。但「装一个 npm 包必然改 lock 文件」「配 alias 必然改 tsconfig」是**确定性、可自动推断**的配套关系，却不在 allowed 默认里，于是每次都要人工救火。

**后果**：close 路径在「全 pass」之后凭空多一道人工门，且这道门的成因与 criterion 完成度无关——纯框架工程学问题。会把「终于全 pass」的收口节奏打断。

**置信**：[高]。

---

### F7. 归档版本号管理脆弱 [中]

**现象**：`versions.yaml` 缺失 → close 从 **v0001 重置** → 归档目录 `.goalspec/history/v0001` 与上一版 v0004 不连续（L3019–L3022）。内容其实是 v0005。

**第一性原理根因**：版本号是**框架自身状态**，不应依赖一个可能缺失的外部文件。缺失时应 hard-fail 或从 `history/` 自动推断最大序号 +1，而不是静默重置。

**后果**：归档链断裂，未来追溯/回滚/审计失准。属低频但高迷惑性故障。

**置信**：[高]。

---

## 3. 非框架因素（列出以避免甩锅错位）

| 类别 | 现象 | 证据 | 为何不算框架 |
|---|---|---|---|
| 项目历史债 | main.tsx 16741 行单文件、无 components/presentation/ui 目录、vite 无 `@` 别名 | L130–L134 | 框架正是来治这个的；债是项目的 |
| intake 源不准 | 后端路径 `src/velentrade/` 与 prompt 假设不符，Master 一度在 frontend 下 find | L92–L113 | capture 阶段 source 校验可加强，但根因是项目未提供准确 inventory |
| AI 工具使用 | cwd 持久化到 frontend 致后端命令失效 | L107 | 工具行为，非框架 |
| AI 模型/调度 | subagent 反复中断、停下问方向需重派 | L2398–L2423 | 模型稳定性，非框架 |
| baseline 噪音 | 16–17 个预存在 vitest fail（authGate/v2AgentOverview） | L2858 | 项目预存在，框架已识别为 baseline |

---

## 4. 优化建议（对应 F1–F7）

> 原则：每条建议都对应一个**门禁或自动化**，而非更多文档。「多写一句 reference」治不了 advice-vs-gap 的病。

### 针对 F1（judgment 形式主义）—— 最高优先

**J1. 强制结构化人工确认协议**：judgment criterion 的人工确认不允许用自由文本「确认达标」收尾。门禁要求 evidence 里必须有 `human_review` 子结构：
```yaml
human_review:
  reviewer: <user-id>
  reviewed_at: <iso8601>
  per_item:           # 强制逐项，禁止批量背书
    - page: admin-users
      dimensions_met: [container, table, label, grouping, copy]  # 勾选实际看过的
      notes: "..."
  coverage: "5/5 pages × ≥4 dims"
```
缺 `per_item` 或 `dimensions_met` 与 criterion 定义维度不交集 → 拒绝 verdict。落地：`judge.sh` apply 前做 schema 校验。[高]

**J2. 禁止 judgment evidence 标 `reproducible: true` + 用无关 command 占位**：P2-002 那条 `ls *.png ≥ 8` 的 sensor command 与 criterion 无关，却以 reproducible 身份贡献了「可复现」假象。规则：judgment/runtime_boundary=manual_observation 的 evidence，`reproducible` 必须 `false`，sensor 不重跑，且 verdict reason 必须写明「本条为人工观察，无 objective gate」——让虚弱性**显式**而非隐式。[高]

### 针对 F2（超大 goal）—— 高优先

**G1. freeze 门禁加 criteria 数量闸**：required criteria > 30（或 > profile 阈值）时，freeze **拒绝**并要求：要么拆 goal，要么显式签署 `override: large_goal` 并强制双 AI review + 强制 split-plan。让「硬塞」变成一个有痕迹、有摩擦的明示决定，而非默认通行。[高]

**G2. cap 偏移反问**：`max_iterations` 设为默认值 N 倍（如 ≥3×）时，freeze/close 反问「为何不拆」并记入 trace。本案 400 = 10×40，本应触发。[中]

### 针对 F3（ceremony tax）—— 高优先

**E1. 提供 `verdict` 高层命令**：`goalspec verdict new <crit> --pass|--insufficient --evidence <ev-ids>... --reason <file>`，内部完成 hash 计算 + schema 校验 + sensor + apply 一步到位。消灭「手抄 contract_hash 49 遍 + bash 手算 hash + heredoc 拼 YAML」。[高]

**E2. evidence 不再内嵌 contract_hash 全串**：改为 evidence 文件整体绑定当前 contract（顶部声明一次），单条 evidence 只保留 `criteria_refs/evidence_requirement_refs/command/...`。contract 漂移由全局校验一次性检测（`evidence check` 已有雏形，L674）。[高]

**E3. evidence template/verdict 校验前置**：在 `evidence check` 阶段就跑 YAML schema 校验，而不是等到 `judge apply` 才报 `Coverage audit:` 冒号缺失（L2270）。[中]

### 针对 F4（sensor 阻塞）—— 中优先

**S1. sensor 结果按 evidence_hash 缓存**：同一条 evidence（command + contract_hash 指纹不变）在本次 close 周期内只跑一次，多 verdict 共引直接复用。[高]

**S2. 独立 evidence 并行重跑**，整体加 wall-clock 预算与进度输出。[中]

**S3. 收紧 `reproducible: false` 的滥用**：要求 `reproducible: false` 必须带 `non_reproducible_reason: slow|flaky|destructive`，且 `slow` 类要求 evidence 至少在 close 时被**显式重跑一次**（即使不进 sensor 缓存）。挡住「慢就豁免」的逃生阀。[中]

### 针对 F5（advisory 无效）—— 高优先

**A1. RALPH_WIGGUM / SMOKE 升级为可配置 blocker**：profile 可设 `enforce_objective_gate: true`，当 pass verdict 中 objective-gate 覆盖率 < 阈值（如 <30%）时 **close 拒绝**，必须追加 smoke / e2e / production-gate evidence 或显式 human override（留痕）。[高]

**A2. close package 顶部强制展示「证据强度分布」**：objective / runtime / static-assertion / manual 各占比，让合入者无法不看见虚弱性。[中]

### 针对 F6（scope 配套）—— 中优先

**P1. scope 自动识别配套文件**：`npm` 包安装触发 `package.json`+`lock` 联动、vite/webpack alias 触发 `tsconfig` paths 联动——这类确定性配套在 `scope amend` 时自动提议或免审。或允许 scope 声明 `derived_paths` 规则。[中]

**P2. test-results/ 等已知 artifact 垃圾默认进 framework `.gitignore` 模板**，不进 scope 判定。[中]

### 针对 F7（版本号）—— 低优先但简单

**V1. versions.yaml 缺失时从 `history/` 推断 max+1，并 warning**；不静默重置。[高 易]

**V2. close 前校验归档连续性**，断裂则 warning（不阻塞）。[低]

---

## 5. 优先级矩阵

| 建议 | 严重度 | 改造量 | 预期收益 |
|---|---|---|---|
| J1 结构化人工确认 | 诚实性 | 中 | 直接堵 F1 漏洞 |
| J2 禁 reproducible 占位 | 诚实性 | 小 | 让虚弱显式 |
| A1 advisory→blocker | 诚实性 | 中 | 堵 F5 系统级漏洞 |
| G1 freeze 数量闸 | 效率/正确 | 小 | 源头治 F2 |
| E1 verdict 高层命令 | 效率 | 中 | 砍 F3 仪式 |
| E2 去冗余 hash | 效率 | 小 | 砍 F3 仪式 |
| S1 sensor 缓存 | 效率 | 中 | 解 F4 |
| V1 版本号推断 | 正确性 | 小 | 修 F7 |
| P1 scope 配套 | 体验 | 中 | 解 F6 |

**若只能做三件**：J1（堵诚实性漏洞）、A1（让告警长牙）、G1（源头治超大 goal）。这三条直接对应框架存在的核心理由。

---

## 6. 对抗性审查（self-review）

> 本节是对第 2、4 节的自我反驳。目的不是走形式，是找出我自己的过度归纳、证据不足、建议的第二阶不良后果。审查后给出修订结论。

### 6.1 对「F1 = 诚实性缺陷」的反驳

**R1.1 单例越界（最关键）。** 日志只能看到用户输入了「确认达标」4 字，**看不到用户在 IDE 里的实际行为**。把「无法证明用户逐张看了」直接叙述成近乎「造假」，是 induction 越界。我原文虽写了「机制上无法区分」，但整段语气容易让人读成「这次就是虚假确认」——这不 fair。
→ **修订**：F1 的定性应从「诚实性缺陷」下调为「**诚实性的内在边界**」+ 一个实打实的可改进点（reproducible 占位制造客观假象）。本次实施的具体诚实性是**未知**（取决于用户实际行为），不是「已证伪」。[高]→[高/定性收窄]

**R1.2 judgment criterion 本就无法用机器保证。** 任何「人工确认」都能被懒人绕过。J1 强制 `per_item` 逐项勾选，会触发 **checkbox fatigue**——用户可能从「确认达标」退化成「全勾」，结构化并不等于诚实，反而可能更不严肃。这跟 J1 的初衷相悖。
→ **修订**：J1 的目标应表述为「**提高绕过成本 + 留可审计痕迹**」，而非「保证诚实」（后者不可能）。同时降低对 J1 效果的预期。新增风险注记。

**R1.3 J2 有反效果。** 禁止 judgment evidence 标 `reproducible:true` 是对的，但若一刀切，某些「人工观察 + 客观 artifact 存在性」混合型 evidence 会失去 artifact 校验。需保留「artifact 存在性可 reproducible，但视觉判断标 manual」的拆分能力，而不是整体禁 reproducible。

### 6.2 对「F2 = 高优先 / 源头」的反驳

**R2.1 87 criteria 也许本来就该是一个 goal。** 「UI/UX 全面优化、系统性消除 10 个问题模式」在业务上是一个连贯价值单元。强行拆成 foundation/stop-bleeding/visual 多个 goal，要付多次固定税、引入 goal 间依赖与 partial delivery。框架 goal-split.md 自己也警告「每个 goal 付一次税」。**拆了未必更好**。
→ 这是强反驳。**F2 的真正问题也许不是「87 太大」，而是「87 在单 goal 下，仪式成本（F3）+ sensor 阻塞（F4）被放大到不可承受」**。治本的杠杆在降仪式，而不是禁大 goal。

**R2.2 G1（freeze 拦截 >30）会误伤合理大改造。** G2（cap 倍数反问）带家长式管理味。
→ **修订**：G1 从「拒绝 freeze」降为「**提示 + 强制留痕 override**」（不阻塞，但把「明知超标仍硬塞」变成一个有痕迹的明示决定）。G2 保留但仅留痕、不阻止。F2 严重度从「高优先源头」调整为「中——更多是 F3/F4 的放大器」。

### 6.3 对「F3 / 建议 E1–E3」的反驳

**R3.1 E2（去冗余 hash）破坏自包含性。** 当前每条 evidence 内嵌 contract_hash，使单条 evidence 可独立校验是否 stale；全局声明一次后，evidence 被部分复制/迁移会失校验。
→ **修订**：E2 改为「**保留 hash 字段，但由工具自动填充/校验，不由人手抄**」。E1 高层命令已隐含这点。E2 单列价值下降，并入 E1。

**R3.2 「框架没有 verdict 高层命令」未经全量核实。** 我只看了 Explore agent 的 medium 广度摘要，没读全部 commands。万一框架已有类似封装只是本案没用？
→ **修订**：E1 的存在性断言置信度从 [高] 降为 [中]（需先核实 `goalspec` CLI 是否真的没有）；但即便有，本案证明该封装没被用上，仍是 discoverability 问题。

### 6.4 对「F4 / 建议 S1–S3」的反驳

**R4.1 S1 缓存有正确性风险。** sensor 重跑的本意是「此刻 command 真的退出 0」。缓存可能给过期结果，尤其 close 最终门禁。
→ **修订**：S1 必须限定为「**同一 close 周期内、command+contract_hash 指纹不变才复用**；close 最终门禁仍须 fresh 全跑一次」。我原文有「本次 close 周期」字样，但需强调 close 终检不缓存。

**R4.2 F4 严重度可能虚高。** 分开 apply 是 workaround，Master 顺利解决，未真正阻塞 close。这是体验问题而非正确性问题。
→ **修订**：F4 维持 [中] 但注明「体验型，非正确性」。S3（收紧 reproducible:false 滥用）才是 F4 里真正沾正确性的子问题。

### 6.5 对「F5 / 建议 A1」的反驳

**R5.1 A1 硬门禁会催生假 objective gate。** 早期项目本就没有 e2e smoke。强制 objective-gate 覆盖率，可能让项目永远 close 不了，或更糟——逼用户写**敷衍的 smoke 来凑数**，这本身就是一种 reward hacking，与框架初衷相悖。和 R1.2 的 checkbox fatigue 同构。
→ **修订**：A1 必须是「**可配置 + human override 留痕**」，且阈值要保守（不是 30%，可能 15–20% 起步），override 路径要显眼。强调「让虚弱显式」而非「强制达标」。

**R5.2 把 advisory 升 blocker，可能违背框架「human in the loop」哲学。** 框架设计也许是「我告诉你虚弱在哪，决定权给人」。
→ 部分成立。所以 A1 默认仍应是 advisory，只在 profile 显式开启时成 blocker。我原文写了「可配置」，OK，但需把「默认值」讲清楚：**默认 advisory，可选 blocker**。

### 6.6 对整体方法论的自我批判

**M1 单例归纳（最大弱点）。** n=1，且这 1 例恰好是「超大 goal（87）+ UI 视觉类（judgment 重）+ 大量 fixture 测试（sensor 慢）」的极端组合，放大了特定摩擦。一个 15-criteria 后端 goal 可能根本遇不到 F1/F4。**外推到「框架一般」时，置信度整体应下调一档**。

**M2 框架设计意图 vs 本案临时配置未充分区分。** cap=400 是本案配置（默认 40）；我有时把它当框架问题叙述，需厘清——cap 默认值 40 其实是合理的，问题是「调高时不反问」。

**M3 未读全部框架源码。** 部分「框架缺 X」的断言（E1）基于 medium 广度摘要，可能漏判。

### 6.7 审查后的修订结论

经对抗性审查，前文结论需做如下调整：

| 项 | 原结论 | 审查后修订 |
|---|---|---|
| F1 定性 | 诚实性缺陷（最严重） | 诚实性的**内在边界** + reproducible 占位假象（可改）。本次诚实性**未知**，非已证伪 |
| F2 定位 | 高优先源头 | **中**——更多是 F3/F4 的放大器；真正杠杆在降仪式 |
| F1/F5 的建议目标 | 堵漏洞 / 保证诚实 | **提高绕过成本 + 留可审计痕迹**（不可能保证诚实）；硬门禁必须配 override 留痕，防 checkbox fatigue / 假 gate 反效果 |
| G1 | freeze 拒绝 | **提示 + 强制 override 留痕**（不阻塞） |
| E1 存在性 | [高] | [中]（需先核实 CLI 是否已有封装） |
| E2 | 独立建议 | 并入 E1（保留 hash 但工具自动填充） |
| S1 | 缓存 | 限定同周期；**close 终检必须 fresh** |
| A1 | 升级 blocker | **默认 advisory，可选 blocker**；阈值保守；override 显眼 |
| 整体外推 | 框架一般问题 | **n=1 极端组合**，外推降一档置信度 |

**审查后若只能做三件（修订版）**：
1. **E1**（verdict/evidence 高层命令 + 自动 hash）—— 砍 F3 仪式，是 F2/F4 痛感的真正杠杆，且几乎无反效果；
2. **J2 + A2**（让证据虚弱性**显式**：禁 reproducible 占位 + close package 强制展示证据强度分布）—— 比硬门禁更安全，不催生敷衍；
3. **V1**（版本号缺失推断而非静默重置）—— 低成本、无反效果、修一个真实 bug。

**被我自己驳回、不再优先的建议**：G1 原版（拦截）、J1 原版（强 per_item 保证诚实）、A1 原版（硬 blocker）。它们都在 R2.1/R1.2/R5.1 下暴露了反效果，改为留痕式弱版本。

**保留不变的核心判断** [高]：
- 框架防住了「subagent 撒谎」，但没防住「整条 goal 在低强度证据上自洽合入」——`RALPH_WIGGUM: 95 pass, 0 objective gate` 仍 exit 0 是这条判断的硬证据；
- 大量仪式成本本可由机器承担却被下放给人手算手抄；
- 本案例最大的人工判读不确定性在 P2-002，而该条 evidence 的 sensor command 与 criterion 要求错配（只验 png 存在）是铁证，不依赖「用户是否真的看了」。

---

## 7. 源码核查（实证）—— 哪些属实、是否值得修复

> 本节是对第 2 节 7 条断言的逐条源码核实。方法：精读 `runtime/lib/{fidelity,sensor,close,scope,hash,schema}.sh` + `runtime/commands/{judge,freeze,evidence,close}.sh` + `references/{evidence-writing,criteria-writing,goal-splitting}.md`。结论：**7 条全部属实**，但源码披露了 3 处需修正/深化的信息，并改变了部分建议的优先级。

### 7.1 核实总表

| 断言 | 源码证据 | 判定 |
|---|---|---|
| **F1** judgment evidence 可用 reproducible+无关 command 占位 | `schema.sh:156-170` 唯一校验是「reproducible→command 非空」；不查 command 与 runtime_boundary/criterion 语义相关性。`judge.sh:142-146` pass reason 只 grep 5 token，注释明说「intentionally a lightweight **format** guard」。`judge.sh:190` sensor 只验 exit 0 | **属实，根因精确定位** |
| **F2** freeze 无 criteria 数量门禁、cap 默认 40 无反问 | `freeze.sh` 8 道门禁全是流程完整性（review/approval/schema/worktree），无数量检查；`judge.sh:226` 默认 cap 40；`goal-splitting.md:75` 明确 safe band 10–30 但仅 advice | **属实** |
| **F3/E1** verdict 无高层封装、hash 须手填 | `evidence.sh` 仅 template/check（template 自动填 contract_hash）；`judge.sh` 仅 prompt/apply，apply 校验三个 hash 必须事前填入（L107-134）；无合一命令 | **属实** |
| **F4** sensor 串行无缓存、reproducible:false 全跳过 | `sensor.sh:17` reproducible!=true 直接 return 0（不验证）；`judge.sh:182-195` 每个 pass verdict 对每条 evidence_ref 调 sensor，无跨 verdict 缓存；`evidence-writing.md:74` 自承「慢命令拖累 loop」但无方案 | **属实** |
| **F5** RALPH_WIGGUM 从不阻塞 close | `fidelity.sh:128` 纯 warning；`fidelity.sh:139-141` 仅 `enforce_on_close=true AND smoke failed` 才 return 1；all-soft（无 smoke）时 gate_passed 恒 true（L101-102）；`close.sh:105-111` 据此不 fail | **属实** |
| **F6** scope 无配套文件自动识别 | `scope.sh:302-312` 纯 pattern matching；`scope.sh:79-93` 有 suggest 但粒度为顶层 `/**`（过粗），仍需人工 `scope amend` | **属实** |
| **F7** versions.yaml 缺失→v0001 静默重置 | `close.sh:484-489` `.versions \| length`，缺失 `|| echo 0` → v0001；不扫描 `history/` | **属实** |

### 7.2 源码驱动的 3 处修正（改变建议优先级）

**修正①（重要）：F5 不是「缺机制」，是「整个 objective-gate 层 opt-in 默认关」。**
我原 A1 建议「升级为可配置 blocker」——但框架**已有** `fidelity.enforce_on_close` opt-in（`fidelity.sh:30-31`）。真正缺口是：
- (a) 默认 false；
- (b) 即使开启，**只 block smoke 失败，不 block all-soft**（`fidelity.sh:139` 只看 `gate_passed`，不看 `objective_gate`）；
- (c) 更深：`final_verification`（`git_delivery.sh:161`）在 profile.yaml 不存在时 **`return 0` 直接跳过**；velentrade 正是 no-profile 项目（`fidelity.sh:15-20` 注释自证）。

→ **A1 修正**：不是「新增 blocker」，是「**让 objective-gate 层默认有一个最低底线**」。最小修复：`fidelity_gate` 在 `verdicts>0 && objective_gate=false`（all-soft）时，即使无 smoke 也应进 `enforce_on_close` 判定或要求显式 override。`fidelity.sh:139-141` 是精确改动点。

**修正②（重要）：F1 的 J2 建议有源码支撑，且是低成本无反效果的修复。**
`schema.sh:156-170` 是精确实现位置。加一条：`completion_level=manual_observation` 或 `runtime_boundary=manual` → `reproducible` 必须 `false`。这堵住 P2-002 那种「manual 判断却用 `ls` 占位伪装可复现客观证据」的漏洞。`evidence-writing.md:55-66` 的 reproducible 专节只讲了「副作用/慢命令要 false」，**没覆盖此 case**——属文档与 schema 双重缺失。J2 从「中优先」升为**高优先、低风险**。

**修正③（中等）：F2 的痛感已被 scoped-reopen 部分缓解，但不彻底。**
`judge.sh:223-225` 注释 + `close.sh:44-60`（criterion_hash+goal_hash）证明：作者已用 scoped-reopen 治愈 v0004 的「reopen 后 mass-re-judge → LOOP_CAPPED」问题。但 scoped-reopen **只解决「reopen 后重判」**，不解决「**首次**跑 87 criteria 的仪式成本」（F3）与「首次 cap 压力」。→ F2 维持属实，但 G1（freeze 数量闸）因可能误伤合理大改造 + scoped-reopen 已分担部分压力，**优先级低于 F3/E1**（降仪式才是杠杆）。

### 7.3 「是否值得修复」ROI 排序（源码核实后）

| 修复 | 改动点 | 价值 | 成本/反效果 | 结论 |
|---|---|---|---|---|
| **J2** schema 禁 manual+reproducible 占位 | `schema.sh:156-170` 加 1 条判定 | 高（堵诚实性漏洞） | 极低 | **必做** |
| **V1** 版本号缺失从 history/ 推断 | `close.sh:484-489` 加 fallback 扫描 | 中（修真实 bug） | 极低 | **必做** |
| **E1** verdict 高层命令（自动 hash） | 新增 `commands/verdict.sh` 或 judge 加 `new` 子命令 | 高（砍 F3 仪式，87-criteria 杠杆） | 中（bash 工程量） | **强烈建议** |
| **A1 修正版** all-soft 进 enforce 判定 | `fidelity.sh:139-141` 扩展条件 | 高（让告警长牙） | 中（需 override 留痕，防催生假 gate） | **强烈建议** |
| **S1** sensor 同周期缓存 | `sensor.sh` + `judge.sh:182` 加缓存层 | 中（解 F4 超时） | 中（close 终检须 fresh） | 建议 |
| **F6** scope suggest 粒度收窄 | `scope.sh:83-86` 建议到文件级而非 `/**` | 中（防顺手过度 allow） | 低 | 建议 |
| **G1** freeze 数量提示（非阻塞） | `freeze.sh` 加 warning + override 留痕 | 中 | 低，但有 scoped-reopen 分担 | 可做 |
| **J1** 强制 per_item 人工确认结构 | verdict schema 加 human_review | 中 | 高（checkbox fatigue） | **暂缓**（J2 已堵更紧要的漏洞） |

### 7.4 最终结论（核实后不变的核心）

1. **第 2 节 7 条断言全部属实**，无一条冤枉框架。源码行号已在 7.1 给出，可逐条复核。
2. **最值得修复的不是「最大」的 F2，而是「最小」的 J2 + V1**——两处都是几行代码、零反效果、修真实漏洞。F2 反而因 scoped-reopen 已分担压力且可能误伤，优先级让位于 F3/E1。
3. **F5 是最深的系统性问题**，但修法不是「加 blocker」（框架已有 opt-in），而是**改变默认值哲学**：objective-gate 层不应在「无 profile」时全部静默缺失——这是 velentrade 两次事故（2026-06-26 的 4 生产 bug + 本次 v0005 的 RALPH_WIGGUM 95/0）的共同根因，框架作者两次都在注释里写下了事故复盘，却两次选择 soft。这是**设计哲学问题，不是 bug**——所以是否「修复」取决于框架定位：若定位为「防呆护栏」，当前 soft-by-default 是缺陷；若定位为「渐进 opt-in 工具」，当前行为自洽，但应在 README 顶部对无 profile 项目明确告警「你没有任何客观门禁」。
4. 我对抗性审查（第 6 节）中**自我驳回的建议（G1 原版、J1 原版、A1 原版）维持驳回**——源码核实后，J2 + E1 + A1修正版 + V1 是更优解，反效果更小。
