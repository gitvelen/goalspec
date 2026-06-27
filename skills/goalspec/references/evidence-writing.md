# Evidence Writing

Subagent 产出 evidence 时使用本指南。目的：让 evidence 是**可被 Master 校验、可被 sensor 复现**的可观察事实，而不是自述。

## evidence 是什么

evidence = 绑定到 Criteria 的**可观察事实**。它记录"做了什么、命令是什么、结果如何"，并回指具体 criterion 与 evidence_requirement。evidence **不是**执行进度或完成状态——完成判定是 Master 的职责（经 `judge apply`）；Subagent 产 evidence，永远不能宣布最终成功。

只有 `evaluated_by: master` 的 verdict 能判定 Criteria；测试通过、Subagent 自述、evidence 文本本身都不构成收口。

## 何时用

实施期间（`/goalspec run` 的循环内）。Subagent 收集到能证明某 criterion 的事实时，写入 `.goalspec/active/evidence.yaml`。

骨架由命令生成：

```bash
.goalspec/goalspec evidence template <criteria_id>
```

它按 contract 里该 criterion 的 `evidence_requirement_refs` 拉出相关要求，产出一条骨架（id / contract_hash / criteria_refs / evidence_requirement_refs 已填，command / exit_code / artifact_paths 留给 Subagent）。

写完用：

```bash
.goalspec/goalspec evidence check
```

校验所有 evidence 的 `contract_hash` 一致 + schema（见下）。

## 每条 evidence 的字段

| 字段 | 含义 | 注意 |
|---|---|---|
| `id` | EV-NNN | 唯一；template 自动编号 |
| `contract_hash` | 绑定当前 frozen contract | 必须与当前 contract 一致，否则 stale（`judge apply` 拒绝引用它的 pass verdict） |
| `criteria_refs` | 绑定到哪些 criterion | 至少一个；evidence 必须回指 criterion |
| `evidence_requirement_refs` | 满足哪些 evidence_requirement | pass verdict 要求引用的 evidence 覆盖 criterion 的全部 required reqs |
| `command` | 产生该事实的命令 | `reproducible:true` 时必填非空；sensor 会重跑 |
| `exit_code` | 命令退出码 | 记录用；sensor 重跑时**不信**它，只信重跑结果 |
| `artifact_paths` | 产物路径（日志、截图、trace） | 可空 |
| `runtime_boundary` | browser / api / integration / unit | 强度要匹配 claim（见下） |
| `reproducible` | true / false | **最易错字段**，见下专节 |
| `produced_by` | 固定 `subagent` | Master 不产 evidence |
| `residual_risk` | {level, notes} | 诚实标注残留风险 |

## runtime_boundary 要匹配 claim 强度

Master 的 Coverage Audit 会分类 evidence 强度（real runtime / browser / api / integration / unit / fixture / mock / static / manual），并判断强度是否足以证明 claim：

- **集成级 claim**（如"用户登录返回 200"）用 unit evidence 是**伪证明** → Master 判 `insufficient`。
- **unit claim** 用 integration evidence 是浪费（但不算伪证明）。
- 选刚好够的最弱边界——省成本且不失真。

## reproducible：最易错的字段

`reproducible: true` 的语义很重：**sensor 会在每次 `judge apply` 时，在 PROJECT_ROOT 重跑这条 command**（`sensor.sh`：`cd "$PROJECT_ROOT" && bash -lc "$cmd"`），退出码非 0 → 该 pass verdict 被**拒绝**（不自动降级，`judge.sh`）。这是 goalspec 闭合"pass verdict 建立在 Subagent 自述 exit_code 上"缺口的关键机制。

因此：

1. **只把确定性、无副作用的命令标 `true`**：纯读操作、`pytest`、`npm test`、lint、typecheck、build——重跑结果稳定。
2. **有副作用的命令必须标 `false`**：发邮件、写外部系统、扣款、`curl -X POST` 改状态、网络修改。sensor 不重跑 `false` 的 evidence（副作用安全）。schema 拒绝 `reproducible:true` + 空 command。
3. **flaky 命令不要标 `true`**：flaky test（同代码时绿时红）标 true 会让 sensor verdict 时拒时过——直接破坏 run-loop 的 stop condition（loop 要么改没坏的东西、要么停在坏的状态）。**先修 flaky，或标 `false`**。
4. **危险命令额外警惕**：即使你确信"可复现"，含 `rm -rf`、`mail`、`charge`、`DROP`、外部写入的命令标 `true` 会让 sensor 每次 judge 都真跑它。默认标 `false`，除非你明确希望每次 judge 都重跑。

> 一句话：`reproducible` 不是"这个 evidence 看起来可复现"，而是"**我授权 sensor 在每次 judge 时重跑这条命令**"。

## command 要自包含

sensor 重跑的方式是 `cd "$PROJECT_ROOT" && bash -lc "$command"`。所以 command 必须：

- 在 PROJECT_ROOT 下可跑（不要依赖当前会话的 `cd`）。
- 自包含（env / 路径显式，不依赖交互式 shell 的别名）。
- 快——每次 judge 都重跑 reproducible evidence；慢命令拖累 loop。

## 绑定与覆盖

- evidence 必须 `criteria_refs` 回指 criterion；无主 evidence 不被引用。
- pass verdict 要求引用的 evidence **覆盖 criterion 的全部 `evidence_requirement_refs`**（`judge apply` 检查）。写 evidence 前先看 criterion 要哪些 requirement，逐个覆盖。
- evidence 的 `contract_hash` 必须等于当前 frozen contract hash；contract 变了（reopen 重 freeze），旧 evidence 全部 stale，不能直接复用，需刷新。

## 好坏示例

**Bad — 自述式、无命令、伪复现**：

```yaml
- id: EV-001
  criteria_refs: ["CRIT-001"]
  command: ""
  exit_code: 0
  reproducible: true        # ← reproducible:true 但 command 空，schema 拒绝
  runtime_boundary: unit
  residual_risk: {level: none, notes: "测试都过了"}  # ← 自述，非可观察事实
```

**Bad — 有副作用却标 reproducible**：

```yaml
- id: EV-002
  criteria_refs: ["CRIT-PAY"]
  command: "scripts/charge-test-card.sh"   # 会真扣款
  reproducible: true                        # ← sensor 每次 judge 真扣款！必须 false
```

**Good — 确定性、自包含、强度匹配**：

```yaml
- id: EV-003
  contract_hash: "sha256:..."
  criteria_refs: ["CRIT-LOGIN"]
  evidence_requirement_refs: ["EVIDREQ-LOGIN-200"]
  command: "pytest -q tests/auth/test_login.py::test_owner_login_returns_200"
  exit_code: 0
  artifact_paths: ["tmp/auth-login.log"]
  runtime_boundary: integration
  reproducible: true            # 纯跑测试，无副作用，结果稳定
  produced_by: subagent
  residual_risk: {level: low, notes: "仅覆盖 owner 角色正例；负向鉴权另见 EV-004"}
```

## 产出

追加到 `.goalspec/active/evidence.yaml` 的 `evidence:` 下。然后交给 Master 经 `goalspec judge apply` 判定——evidence 本身不关闭 criterion。
