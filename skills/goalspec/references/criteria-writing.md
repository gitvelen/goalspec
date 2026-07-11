# Criteria Writing

Compiler 起草 `contract.yaml` 的 Criteria 时使用本指南（freeze 前）。目的：让 Criteria
**完整、有效、可验收**，使下游 run-loop 能对每一条判出清晰的 pass/fail 并收敛，而非空耗。

## 何时用

`goalspec compile` 之后、`freeze` 之前。Compiler 已读入 `goal.md`、project memory、
constraints、regression-suite，正要填写 `criteria:[]` 与 `evidence_requirements:[]`。

## 输入

三视角起草的关键在于**各读不同的源材料（正交输入源）**，否则视角独立是假象、产出会同质化：

- `.goalspec/active/goal.md`：尤其 Intent / Narrative / **Success Model** / Scope / Risk Scan
  —— **产品视角与测试视角的源**（前者读功能结构，后者读质量维度矩阵）。
- `.goalspec/project/*.yaml`：project memory、constraints、regression-suite；以及
  `.goalspec/active/constraint-suggestions.yaml`（若已应用）—— **工程视角的源**（从 constraint
  空间反向推 criteria，不从 goal.md 功能分支重复产出）。

---

## 设计原则：三视角必须正交独立

覆盖度有两个正交的轴，外加一个被忽视的约束空间，构成三个**输入源互不重叠**的视角：

| 视角 | 正交输入源 | 回答 | 失败则 |
|---|---|---|---|
| **产品覆盖**（纵轴） | goal.md 功能分支 | goal 要实现哪些**用户可感知**的功能 | 漏功能分支 |
| **测试专家**（横轴） | goal.md × 质量维度矩阵 | 每个功能在**正常/异常/边界/权限/集成/降级**下该是什么样 | 漏质量维度 |
| **工程专家**（约束空间） | constraints + project memory + regression-suite | 实现 goal 隐含哪些**技术契约、与哪些 constraint 交互** | 漏 constraint 一致性 |

> 旧流程的缺陷：测试视角"对 Step 1 的每个 goal branch 检查维度"——输入是产品视角已识别的分支，
> **覆盖上限被产品视角锁死**；产品漏识别的分支，测试永远补不到。工程视角又依附产品草稿做改写，
> 三者同源、互相锚定。新流程让三者从不同源材料**独立**产出，再合并。

---

## 起草四步

### Step 1 — 三视角并行独立起草

三个子视角**各自独立**产出 criteria（可由独立 subagent 并行执行以消除锚定），**互不参考彼此草稿**。
合并是 Step 2 的事，不在这一步做。

#### 1a. 产品覆盖视角（纵轴，主线）

把 `goal.md` 拆成原子「目标分支」，**每个分支必须被至少一条 Criterion 覆盖**，并产出一张
`goal_branch → criterion id(s)` 追溯表。这是纵向完整性的根。逐源扫描：

- **Intent**：每个 scenario（谁 / 什么场景 / 什么变更）→ ≥1 条 criterion。
- **Narrative**：正常流、每条失败路径、每个状态变化 → 各自 criterion。
- **Success Model（最富矿，逐字段翻译）**：
  - `user_visible_success` → 正向 criterion（用户可感知的行为）；
  - `system_observable_success` → 正向 criterion（系统可观察的状态/输出）；
  - `must_not_happen` → **每条都变成一条负向 criterion**（"不发生 X"），**不得合并、不得省略、不得静默跳过**；
  - `minimum_acceptable_result` → 一条「最低线」criterion（低于此即未完成）；
  - `final_completion_signal` → 那条 `final: true` criterion（收口信号）。
- **Scope**：`in_scope` → criteria；`out_of_scope` 与非目标 → **写进 constraints 或负向
  criterion，而不是正向 criteria**（避免把不做的事写成成功标准）。
- **Risk Scan**：**每条结论都必须评估**——落成对应 criterion，或显式移入 constraints；若判定与本 goal 无关而跳过，必须在 `questions.yaml` 写明理由，**不得静默遗漏**（曾发生 C 类数据隔离、migration schema 两条结论被静默跳过、零覆盖的案例）。

> 追溯表不是脑内过一遍，而是**先写下来的可见产物**：逐 section 列出 goal.md 的每个原子分支，
> 每行标注 `→ CRIT-xxx` 或 `→ constraint` 或 `→ 跳过(理由写入 questions.yaml)`。Step 2 的覆盖矩阵
> 会拿它做行轴。

#### 1b. 测试专家视角（横轴，独立于 1a）

**不参考 1a 的追溯表**，独立从 Success Model + goal 推断每个功能在各种条件下该表现成什么样。
按 goal 暗示的范围检查下列维度是否需要落成 criterion；**每一项都要写成「有可观察结果」的具体
criterion，而非含糊愿望**：

- **正常路径**：主流程的预期行为。
- **变体路径**：可替换输入、可替换状态、可替换角色。
- **负向路径**：非法输入、错误条件、权限不足的拒绝行为。
- **边界条件**：空集、单元素、极值、off-by-one、并发/竞态、超时阈值。
- **权限与安全**：鉴权、授权、密钥处理、注入面、越权访问。
- **数据生命周期**：创建、更新、删除、保留期、迁移、幂等性。
- **集成边界**：上游/下游契约、外部 API 行为、网络故障。
- **失败降级**：部分失败、超时、重试语义、降级后的用户可见行为。
- **非功能底线**：性能基线、可访问性、i18n 等——**仅当 goal 暗示时**才写，不要凭空加。
- **非目标**：显式声明「不要求」的，落成负向 criterion 或 constraint，防 scope 蔓延。

> 判断标准：每个维度你能否写出一个**能被 evidence 证明、能描述 fail 长什么样**的断言；写不出，
> 说明该维度本 goal 不涉及，标 N/A。**独立性是关键**：正因为不看 1a，测试视角才能补到 1a 漏掉的
> 分支——它和 1a 的并集才是完整覆盖。

#### 1c. 工程专家视角（constraint 空间反向推，独立于 1a/1b）

**不从 goal.md 功能分支重复产出**（那是 1a 的地盘），而是读 `.goalspec/project/*.yaml` 的
constraints + project memory + regression-suite，反向推出产品/测试视角都不会写的 criteria：

- **constraint 一致性断言**：goal 要做 X，但 constraint C 限制 Y → "X 的实现不得违反 C"。
  产品视角不管 constraint，测试视角管维度不管 constraint 交互——这类目前最易零覆盖。
- **隐含技术契约**：实现 goal 隐含的技术前提。如 goal 说"用户能搜索"，工程视角独立识别"搜索
  结果必须分页""不得在主库建索引""数据迁移期间搜索不得中断"等成功标准。
- **跨模块 / 跨系统契约**：goal 触及多模块时，模块间依赖断言、接口契约、顺序前提。
- **kind 决策与可判定性约束**：哪些断言能 `machine`、哪些注定 `judgment`（需人类/Master 裁决）、
  judgment 的代价（卡 close 直到人工裁决）——尽量重写成 machine 可判。

> 这一步填补旧流程完全缺失的盲区：**从 constraint 空间反向推 criteria**。constraints 是 goalspec
> 的一等公民（见 `constraint-extraction.md`），不利用它反推成功标准是浪费。

### Step 2 — 合并 + 覆盖矩阵（可量化的覆盖度量）

把 1a / 1b / 1c 三来源 **union → 语义去重 → 冲突解决**，并产出一张**覆盖矩阵**作为可见、可计算的
覆盖度量（解决"覆盖难以量化"）：

- **矩阵结构**：行 = goal_branch（含每条 `must_not_happen`、每条 Risk Scan 结论），列 = 质量维度
  （正常/负向/边界/权限/数据/集成/降级/非功能…），格 = `CRIT-xxx` 或 `N/A(理由)`。
- **可量化**：覆盖率 = 已覆盖格 / 总格；漏项 = 空格数。给人类 review 和 freeze 一个客观数字，
  而非"我觉得覆盖全了"。

核对两条不变量：

1. **无漏分支**：矩阵每行至少有一个 criterion 或带理由的 `N/A`——**尤其是 `must_not_happen` 的每
   一条和 Risk Scan 的每一条结论**，必须各有一条 criterion 或 constraint 兜住（这两类最易被静默
   遗漏）；
2. **无 orphan**：每条 criterion 都能回指到某行（某个 goal_branch × 维度）；回指不上的，丢弃或移入
   `optional_criteria`。

> 三个来源可能产出语义重叠的 criteria（如 1a 写"搜索返回结果"、1b 写"搜索正常路径返回结果"）。
> 合并时去重为一条；冲突（如一条要分页、一条禁止分页）必须解决并记入 `questions.yaml`。

### Step 3 — 质量门禁（工程约束 + 可验收性约束）

对合并后的**每条** criterion 施加两组约束。`schema.sh` 在 freeze 会兜底最严重的违规（模糊词、
实现泄漏、悬空引用、无 final、allowed_paths 空）；这一步的职责是**补 schema.sh 拦不住的盲区**，
让每条一次写对、能在 run-loop 收敛。

#### 工程约束

- **原子化**：一条只表达一个可验证断言。含 `AND` 的复合断言要拆——否则部分通过时 Master 判
  不出 pass/fail，loop 会 stall。含 `OR` 通常说明标准过弱，也要拆或收紧。（拆分示例见下。）
- **相关**：能追溯到覆盖矩阵的某个格子。追溯不上的不入 required。
- **最小化**：不过度规约，不框死无关细节。
- **无实现泄漏**：statement 里**不得**出现技术选型、文件路径、函数名、类名、任务步骤（会被
  `schema.sh` 拒，命中 `实现|重构|使用|implement|refactor|use|create file|edit file|修改`）。
- **kind 正确**：`machine` 优先（run-loop 可自动推进）；`judgment` 仅在确实无法机器判定时使用，
  且要意识到它会卡住 close 直到人工裁决。**但「machine 优先」不等于「machine 强制」**：效用/统计类
  成功标准（如「回测结果能否支撑投产判断」「因子 IC 是否有预测力」「前端是否真好用」）本质不可
  pass/fail 机器判定——强行写成 machine 会退化成存在性弱断言（「页面能加载」），反而丢失验收力。
  这类用 `kind: judgment` 显式承接，并在 statement 写清人类裁决口径，不要为绕开 judgment 代价而
  把效用验收阉割成能力存在。
- **与 constraints 一致**：不与已有 constraint 矛盾（呼应 1c）。

> **盲区示例 — AND 复合断言拆分**（schema.sh 不查原子化，是 loop stall 主因）：
>
> 坏（复合，部分通过时判不出 pass/fail）：
> ```yaml
> statement: 搜索返回结果且结果按相关性排序且响应在 300ms 内
> ```
> 改写为多条原子：
> ```yaml
> - statement: 搜索对合法 query 返回非空结果集
> - statement: 搜索结果按相关性降序排列
> - statement: 搜索在 100 RPS 下 P95 延迟 ≤ 300ms
> ```

#### 可验收性约束

每条 criterion 必须**可被 Master 从 evidence 判成 pass 或 fail**，并保证 loop 能收敛：

- **evidence 可解析**：`evidence_requirement_refs` 指向的 id 必须在 `evidence_requirements:[]`
  中有定义（`schema.sh` 拒绝 dangling 引用）。先写好 `evidence_requirements`，再引用。
- **evidence 强度匹配**：所选 `runtime_boundary`（browser / api / integration / unit）的强度
  要足以证明该断言。（强度匹配示例见下。）
- **statement 无歧义、无模糊词**：不得命中 `合理|良好|优化|正确|完整|充分支持|reasonable|
  good|optimized|correct|complete|proper|properly`（`schema.sh` 会拒）。用可测量的量代替。
- **可判定的 fail**：**能描述「不通过时长什么样」**。描述不出，说明这条判不出 fail，Master 会
  在 `insufficient` 与 `pass` 之间摇摆，loop 空耗——**必须重写**。（改写示例见下。）
- **恰好一条 `final: true`**：对应 Success Model 的 `final_completion_signal`，是收口的最终信号。

> **盲区示例 — evidence 强度匹配**（schema.sh 不查强度，伪证明会让 Master 判 `insufficient`）：
>
> 坏（集成级断言配 unit evidence = 伪证明）：
> ```yaml
> - id: CRIT-SEARCH-001
>   statement: 搜索端到端返回相关结果
>   evidence_requirement_refs: [EVIDREQ-UNIT]   # ← unit 级压不住端到端断言
> ```
> 改写（配 integration evidence）：
> ```yaml
> - id: CRIT-SEARCH-001
>   statement: 搜索端到端返回相关结果
>   evidence_requirement_refs: [EVIDREQ-E2E]
> ```
>
> **盲区示例 — 可判定的 fail**（schema.sh 不查可判性）：
>
> 坏（描述不出 fail 长什么样）：
> ```yaml
> statement: 系统应有良好的错误处理
> ```
> 改写（能描述 fail：注入错误后用户侧应看到确定性提示，否则 fail）：
> ```yaml
> statement: 当下游连续 10s 超时，用户侧显示明确的"暂时不可用"提示而非空白页
> ```

**loop-safety 自检（对整组 criteria）**：

> 若实现是正确的，run-loop 能达到 all-pass 吗？
> 若实现略有偏差，能否判出**清晰的 fail**（而不是 stall 在 `insufficient`）？

任何一条答「否」，该条不可判定，重写或移除——否则它就是让 loop 空耗、`stalled` 兜底的根源。

### Step 4 — 组装与自审

- required Criteria 默认 required，**不要重复写** `required: true`（compiler.md 既有要求）。
- nice-to-have / 优化想法 → `optional_criteria`，**不得阻断收口**。
- 允许的落点域 → `allowed_paths`（宽域 glob，如 `src/**`、`tests/**`）；不得触碰的 →
  `forbidden_paths`（精确集合）。`allowed_paths` 不得为空。
- 锁定的 regression → 作为 `required_regressions` / required evidence 注入。
- **用 Step 2 的覆盖矩阵反向逐条核对**：是否仍有未覆盖的格子——**特别是 `must_not_happen` 与
  Risk Scan 的每一行**？任何空格必须落成 criterion 或显式移入 constraints，不得静默遗漏。是否有新 orphan？
- 完成后用自然语言向人类展示 Goal、Criteria、Constraints、out-of-scope、blocking questions
  （沿用 compiler.md 既有职责），把疑问写入 `questions.yaml`。

---

## 好坏示例（速查表；聚焦 schema.sh 盲区的改写示例见 Step 3）

下列是最基础的"会被 freeze 当场拒"的对照，确保能过 schema.sh；**真正的难点**（AND 拆分、evidence
强度、可判 fail）已就近嵌入 Step 3，请以那里的改写示例为准。

**Bad — 模糊且不可判定**（命中模糊词，无 evidence）：

```yaml
- id: CRIT-BAD-001
  kind: machine
  statement: 系统性能良好且正确          # ← 「良好」「正确」会被 schema.sh 拒
  evidence_requirement_refs: []
```

**Bad — 实现泄漏**（把技术选型/步骤当成功标准）：

```yaml
- id: CRIT-BAD-002
  kind: machine
  statement: 使用 Redis 实现缓存          # ← 「使用」「实现」会被 schema.sh 拒
  evidence_requirement_refs: [EVIDREQ-001]
```

**Good — 正向、可测量、evidence 可证**（覆盖非功能底线维度）：

```yaml
- id: CRIT-PERF-001
  kind: machine
  statement: 在 100 RPS 负载下 /search 的 P95 延迟 ≤ 300ms
  evidence_requirement_refs: [EVIDREQ-PERF]
```

**Good — 负向、覆盖失败降级 + must_not_happen**：

```yaml
- id: CRIT-DEGRADE-001
  kind: machine
  statement: 当上游 X 连续 10s 返回 503 时，用户侧不出现任何可见错误（降级为缓存/默认值）
  evidence_requirement_refs: [EVIDREQ-DEGRADE]
```

配套的 evidence_requirements（id 必须先定义、再被引用）：

```yaml
evidence_requirements:
  - id: EVIDREQ-PERF
    runtime_boundary: integration
    statement: 100 RPS 负载压测采集 P95 延迟
  - id: EVIDREQ-DEGRADE
    runtime_boundary: integration
    statement: 上游 503 注入下观测用户侧无错误
```

## 产出

填入 `.goalspec/active/contract.yaml` 的 `criteria:[]` 与 `evidence_requirements:[]`；
不确定的点写入 `.goalspec/active/questions.yaml`（标记 `blocking` 的必须在 contract review
前解决）。随后交由 contract review（fresh-context 独立评审）与 freeze（schema lint +
门禁）兜底。
