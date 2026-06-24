# Criteria Writing

Compiler 起草 `contract.yaml` 的 Criteria 时使用本指南（freeze 前）。目的：让 Criteria
**完整、有效、可验收**，使下游 run-loop 能对每一条判出清晰的 pass/fail 并收敛，而非空耗。

## 何时用

`goalspec compile` 之后、`freeze` 之前。Compiler 已读入 `goal.md`、project memory、
constraints、regression-suite，正要填写 `criteria:[]` 与 `evidence_requirements:[]`。

## 输入

- `.goalspec/active/goal.md`：尤其 Intent / Narrative / **Success Model** / Scope / Risk Scan。
- `.goalspec/project/*.yaml`：project memory、constraints、regression-suite。
- `.goalspec/active/constraint-suggestions.yaml`（若已应用）。

---

## 起草五步

### Step 1 — 产品覆盖图（主线，先做这一步）

把 `goal.md` 拆成原子「目标分支」，**每个分支必须被至少一条 Criterion 覆盖**，并产出一张
`goal_branch → criterion id(s)` 追溯表。这是完整性的根。逐源扫描：

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

完成扫描后核对两条不变量：

1. **无漏分支**：goal.md 里每个目标分支都出现在追溯表中——**尤其是 `must_not_happen` 的每一条和 Risk Scan 的每一条结论**，必须各有一条 criterion 或 constraint 兜住（这两类最易被静默遗漏）；
2. **无 orphan**：每条 criterion 都能回指到某个 goal branch；回指不上的，丢弃或移入
   `optional_criteria`。

> 追溯表不是脑内过一遍，而是**先写下来的可见产物**：逐 section 列出 goal.md 的每个原子分支，
> 每行标注 `→ CRIT-xxx` 或 `→ constraint` 或 `→ 跳过(理由写入 questions.yaml)`。先有这张表，
> 再写 criteria；Step 5 会拿它反向核对。

> 这一步把 compiler.md 原来那一行提示里漏掉的「产品视角完整性」补上：先保证**该覆盖的都覆盖了**，
> 再谈每条写得好不好。

### Step 2 — 工程专家视角（每条的有效性）

对草拟出的每条 criterion 逐条自检：

- **原子化**：一条只表达一个可验证断言。含 `AND` 的复合断言要拆——否则部分通过时 Master 判
  不出 pass/fail，loop 会 stall。含 `OR` 通常说明标准过弱，也要拆或收紧。
- **相关**：能追溯到某个 goal branch（Step 1）。追溯不上的不入 required。
- **最小化**：不过度规约，不框死无关细节。
- **无实现泄漏**：statement 里**不得**出现技术选型、文件路径、函数名、类名、任务步骤。这类
  内容会被 `schema.sh` 在 freeze 拒绝（命中 `实现|重构|使用|implement|refactor|use|create
  file|edit file|修改`）。实现细节属于 Subagent 的工作，不是成功标准。
- **kind 正确**：
  - `machine`：可从机器可检查的 evidence 自动判定，run-loop 可自动推进；
  - `judgment`：需人类/Master 裁决（无机器证据可判定），会阻塞自动收口——**仅在确实无法机器
    判定时使用**，且要意识到它会卡住 close 直到人工裁决。
- **与 constraints 一致**：不与已有 constraint 矛盾。

### Step 3 — 测试专家视角（每个分支的覆盖完整性）

对 Step 1 的每个 goal branch / scenario，按 goal 暗示的范围检查下列维度是否需要落成
criterion；**每一项都要写成「有可观察结果」的具体 criterion，而非含糊愿望**：

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

> 这一节是把 compiler.md 原那一行「正常/变体/负向/边界/权限安全/数据生命周期/集成/失败降级/
> 非功能/非目标」从清单扩成「逐项怎么写成 Criterion」。判断标准：每个维度你能否写出一个
> **能被 evidence 证明、能描述 fail 长什么样**的断言；写不出，说明该维度本 goal 不涉及，跳过。

### Step 4 — 可验收性 / loop-safety（可判定且能让 loop 收敛）

每条 criterion 必须**可被 Master 从 evidence 判成 pass 或 fail**，并保证 loop 能收敛。逐条确认：

- **evidence 可解析**：`evidence_requirement_refs` 指向的 id 必须在 `evidence_requirements:[]`
  中有定义（`schema.sh` 拒绝 dangling 引用）。先写好 `evidence_requirements`，再引用。
- **evidence 强度匹配**：所选 `runtime_boundary`（browser / api / integration / unit）的强度
  要足以证明该断言。集成级断言用 unit evidence 是伪证明，Master 的 Coverage Audit 会判
  `insufficient`。
- **statement 无歧义、无模糊词**：不得命中 `合理|良好|优化|正确|完整|充分支持|reasonable|
  good|optimized|correct|complete|proper|properly`（`schema.sh` 会拒）。用可测量的量代替
  （数值阈值、可观察事件、确定的输出）。
- **无隐藏的部分通过**：见 Step 2 的原子化要求——含 AND/OR 必须可分解。
- **可判定的 fail**：**能描述「不通过时长什么样」**。描述不出，说明这条判不出 fail，Master 会
  在 `insufficient` 与 `pass` 之间摇摆，loop 空耗——**必须重写**。
- **恰好一条 `final: true`**：对应 Success Model 的 `final_completion_signal`，是收口的最终信号。

**Loop-safety 自检（对整组 criteria）**：

> 若实现是正确的，run-loop 能达到 all-pass 吗？
> 若实现略有偏差，能否判出**清晰的 fail**（而不是 stall 在 `insufficient`）？

任何一条答「否」，该条不可判定，重写或移除——否则它就是让 loop 空耗、`stalled` 兜底的根源。

### Step 5 — 组装与自审

- required Criteria 默认 required，**不要重复写** `required: true`（compiler.md 既有要求）。
- nice-to-have / 优化想法 → `optional_criteria`，**不得阻断收口**。
- 允许的落点域 → `allowed_paths`（宽域 glob，如 `src/**`、`tests/**`）；不得触碰的 →
  `forbidden_paths`（精确集合）。`allowed_paths` 不得为空。
- 锁定的 regression → 作为 `required_regressions` / required evidence 注入。
- **用 Step 1 的覆盖清单反向逐条核对**：是否仍有未覆盖的 goal branch——**特别是 `must_not_happen` 与 Risk Scan 的每一条**？任何未覆盖的分支必须落成 criterion 或显式移入 constraints，不得静默遗漏。是否有新 orphan？
- 完成后用自然语言向人类展示 Goal、Criteria、Constraints、out-of-scope、blocking questions
  （沿用 compiler.md 既有职责），把疑问写入 `questions.yaml`。

---

## 好坏示例（均对齐 `schema.sh` 规则，确保能过 freeze）

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
