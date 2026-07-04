# Goalspec 框架优化方案（实施级）

> 本文是 `reviewgoal.md`（诊断）的对应处方。诊断已逐条源码核实，本文落到文件/函数/伪代码层。
> 设计原则（贯穿）：① 优先改默认值与 schema，不增加使用者手工工序；② 向后兼容（无 profile / 旧 verdict 仍工作）；③ 每条改动可独立 ship、独立验证；④ 不为一次性代码预抽象。

---

## 0. 实施批次总览

| 批次 | 改动 | 改动点 | 工程量 | 反效果 | 何时做 |
|---|---|---|---|---|---|
| **1 必做** | J2 | `lib/schema.sh` 加 1 条判定 | ~10 行 | 极低 | 立即 |
| **1 必做** | V1 | `lib/close.sh` 加 history fallback | ~15 行 | 极低 | 立即 |
| **2 高杠杆** | E1 | `commands/judge.sh` 加 `draft` 子命令 | ~60 行 | 低 | 紧接 |
| **2 需决策** | A1 | `lib/fidelity.sh` 扩展 enforce 语义 | ~20 行 | **中（哲学）** | 决策后 |
| **3 可推迟** | S1 | `lib/sensor.sh` + `judge.sh` 加缓存 | ~50 行 | 中 | 看 F4 痛感 |
| **3 可推迟** | F6 | `lib/scope.sh` suggest 粒度收窄 | ~10 行 | 低 | 顺手 |
| **暂缓** | J1 / G1 | — | — | 高 | 不做 |

---

## 1. 批次 1：必做（零反效果修真实漏洞）

### 1.1 J2 —— 禁止 judgment evidence 伪装可复现

**问题**（`reviewgoal.md` F1）：`schema.sh:156-170` 只查「reproducible→command 非空」。P2-002 用 `completion_level=manual_observation` + `reproducible:true` + `ls *.png` 占位，制造「客观可复现」假象，sensor 只验文件存在。

**现状**：
```bash
# runtime/lib/schema.sh
goalspec_schema_evidence_entry() {
  ...
  repro="$(yq e ".evidence[] | select(.id == \"$id\") | .reproducible // false" "$ef")"
  if [ "$repro" = "true" ]; then
    cmd="$(... .command ...)"
    if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
      echo "evidence $id: reproducible=true requires a non-empty command" >&2; return 1
    fi
  fi
  return 0
}
```

**改后（option A：严格禁止）**：
```bash
  if [ "$repro" = "true" ]; then
    cmd="$(yq e ".evidence[] | select(.id == \"$id\") | .command // \"\"" "$ef")"
    if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
      echo "evidence $id: reproducible=true requires a non-empty command" >&2; return 1
    fi
    # J2: judgment evidence must not masquerade as sensor-verifiable.
    local cl rb
    cl="$(yq e ".evidence[] | select(.id == \"$id\") | .completion_level // \"\"" "$ef")"
    rb="$(yq e ".evidence[] | select(.id == \"$id\") | .runtime_boundary // \"\"" "$ef")"
    if [ "$cl" = "manual_observation" ] || [ "$rb" = "manual" ]; then
      echo "evidence $id: completion_level=manual_observation/runtime_boundary=manual must be reproducible=false — judgment cannot be sensor-verified; cite artifact existence via artifact_paths instead" >&2
      return 1
    fi
  fi
```

**兼容性**：旧 evidence 若同时标 manual + reproducible（极少），`evidence check` 会报错——这是**期望行为**（暴露漏洞），非回归。需在 release note 说明。

**验证**：构造一条 `manual_observation + reproducible:true + ls` evidence → `goalspec evidence check` 应非 0；改为 `reproducible:false` → 通过。

**反效果**：见对抗审查 R1（option A 过严，误伤合法 artifact 校验）→ 给 option B。

---

### 1.2 V1 —— 版本号缺失从 history 推断

**问题**（F7）：`close.sh:484-489` 用 `versions.yaml` 的 length，缺失则 v0001，与 history 不连续。

**现状**：
```bash
goalspec_close_next_history_version() {
  local latest_v next_n
  latest_v="$(yq e '.versions | length' "$GOALSPEC_ROOT/project/versions.yaml" 2>/dev/null || echo 0)"
  next_n=$((latest_v+1))
  printf 'v%04d\n' "$next_n"
}
```

**改后**：
```bash
goalspec_close_next_history_version() {
  local vf="$GOALSPEC_ROOT/project/versions.yaml" next_n
  if [ -f "$vf" ] && [ "$(yq e '.versions | length' "$vf" 2>/dev/null || echo 0)" -gt 0 ]; then
    next_n=$(( $(yq e '.versions | length' "$vf") + 1 ))
  else
    # V1: versions.yaml missing/empty — infer max from history/ to avoid silent reset.
    local max_n=0 d n
    while IFS= read -r d; do
      n="${d#v}"
      [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$max_n" ] && max_n="$n"
    done < <(find "$GOALSPEC_ROOT/history" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null)
    next_n=$((max_n+1))
    [ "$max_n" -gt 0 ] && echo "version-inference: versions.yaml missing/empty; inferred next=v$(printf '%04d' $next_n) from history/ (max existing=v$(printf '%04d' $max_n))" >&2
  fi
  printf 'v%04d\n' "$next_n"
}
```

**兼容性**：versions.yaml 存在时行为完全不变；仅缺失时多一条 stderr warning + 推断。

**验证**：删 versions.yaml、history 有 v0001..v0004 → 应输出 v0005 + warning，而非 v0001。

**反效果**：见 R2（并发/跨 worktree 边缘情况）。

---

## 2. 批次 2：高杠杆 / 需决策

### 2.1 E1 —— `judge draft`：消灭手算 hash

**问题**（F3/E1）：verdict 无 template，apply 前须手填 contract_hash / evidence_hash / evidence_basis_hash。日志里 Master 反复 `source load.sh` 手算、heredoc 拼装、YAML 解析错误。

**设计**：在 `judge.sh` 加 `draft` 子命令——**只自动填 hash 与骨架，不替 Master 写 reason**（保留语义判断责任）。两步但每步都简单：
```
goalspec judge draft CRIT-P2-002 --verdict pass --evidence EV-P2-002-VISUAL > /tmp/v.yaml
# Master 编辑 /tmp/v.yaml 补 reason（Coverage audit），然后：
goalspec judge apply /tmp/v.yaml
```

**伪代码**（`commands/judge.sh` 新增 case）：
```bash
draft)
  crit="${1:-}"; shift
  vcmd="pass"; refs=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --verdict) vcmd="$2"; shift 2 ;;
      --evidence) refs="$2"; shift 2 ;;
      *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
  done
  [ -n "$crit" ] || { echo "usage: judge draft <crit> --verdict <v> --evidence <EV-A,EV-B>" >&2; exit 2; }
  # 校验 contract frozen、crit 存在、evidence 存在（复用 apply 现有校验逻辑）
  ...
  chash="$(goalspec_contract_hash)"
  ehash="$(goalspec_evidence_hash)"
  basis="$(printf '%s\n' "$refs" | tr ',' '\n' | goalspec_evidence_basis_hash)"
  cat <<EOF
criteria_ref: "$crit"
evidence_refs: [$(printf '%s\n' "$refs" | tr ',' '\n' | sed 's/^/"/;s/$/",/' | tr -d '\n' | sed 's/,$//')]
contract_hash: "$chash"
evidence_hash: "$ehash"
evidence_basis_hash: "$basis"
verdict: $vcmd
reason: |-
  Coverage audit:        # required token
  - claim: "TODO"
    evidence: [TODO]
    sufficiency: TODO
    why: "TODO"
  conclusion: "TODO"     # required token
context: fresh
evaluated_by: master
EOF
  ;;
```

**关键设计取舍**：`draft` 不 apply，只输出。原因——apply 要跑 sensor（可能慢）+ 写 verdict.yaml，应在 Master 确认 reason 后才做。draft 零副作用，可反复跑。hash 由工具算，消灭手抄。

**重构机会**：apply 里 L107-134 的 hash/crit/evidence 校验，应抽成 `goalspec_judge_validate_inputs`，供 draft 与 apply 共用——但这是可选清理，不阻塞 E1。

**兼容性**：纯新增子命令，不影响现有 `prompt`/`apply`。

**验证**：`judge draft` 输出的 yaml 直接 `judge apply` 应通过（hash 已填）；故意改 hash 应被 apply 拒绝。

**反效果**：见 R3。

---

### 2.2 A1 —— all-soft close 进 enforce 判定

**问题**（F5）：`fidelity.sh:139-141` 只在 `enforce_on_close=true AND smoke failed` 时 block；all-soft（无 smoke）永不 block。velentrade 两次事故都是 all-soft。

**现状**（`fidelity.sh:138-143`）：
```bash
  # Block only when explicitly enforced AND a smoke command actually failed.
  if [ "$gate_passed" = "false" ] && goalspec_fidelity_enforce_on_close; then
    return 1
  fi
  return 0
```

**改后**（加一个独立开关，**不耦合** enforce_on_close）：
```bash
  if [ "$gate_passed" = "false" ] && goalspec_fidelity_enforce_on_close; then
    return 1
  fi
  # A1: all-soft close (N pass verdicts, 0 objective gate) under enforce_on_all_soft.
  if [ "$objective_gate" = "false" ] && [ "${verdicts:-0}" -gt 0 ] && \
     [ "$(goalspec_fidelity_profile_value '.environment.fidelity.enforce_on_all_soft' 'false')" = "true" ]; then
    echo "RALPH_WIGGUM_BLOCK: ${verdicts} pass verdict(s), 0 backed by an objective gate. Add environment.smoke_tests, or set fidelity.enforce_on_all_soft=false to accept the all-soft close." >&2
    return 1
  fi
  return 0
```

**默认值哲学（核心决策点，非工程）**：
- `enforce_on_all_soft` 默认 **false** → 向后兼容、等于没改（除非项目自觉开启）；
- 默认 **true** → 真正堵住 all-soft，但现有 no-profile 项目 close 会突然失败，破坏兼容。

**我的建议**：默认 **false + init 时若检测到无 smoke_tests，在 profile 里写一行注释 `# WARNING: no objective gate; set enforce_on_all_soft=true after first smoke`**——把默认值问题转成 discoverability 问题，既不破坏兼容，又让缺口显式。真正开启留给项目方决策。

**验证**：配 1 条 smoke 跑通 → objective_gate=true → 不 block；删 smoke + enforce_on_all_soft=true → block；删 smoke + 默认 → warning 不 block。

**反效果**：见 R4（这是哲学问题，不是代码能解决的）。

---

## 3. 批次 3：可推迟

### 3.1 S1 —— sensor 同周期缓存（简要）
`sensor.sh` 无状态，缓存须落盘 `.goalspec/active/.sensor-cache/<eid>-<fp>`，fp = hash(command + contract_hash)。`judge apply` 命中则 skip；`close.sh` 终检前 `rm -rf .sensor-cache` 强制 fresh。**审查后建议推迟**（见 R5，引入状态新故障源，收益不及风险）。

### 3.2 F6 —— scope suggest 粒度（简要）
`scope.sh:83-86` 当前建议 `${f%%/*}/**`（顶层目录，过粗）。改为**同时输出精确文件路径 + 粗 glob 两个 option**，让用户选，而非自动给最粗的。

---

## 4. 暂不做（审查后驳回）

- **J1**（强制 per_item human_review 结构）：checkbox fatigue，结构化≠诚实。J2 已堵住更紧要的「客观假象」漏洞，J1 边际收益低、反效果高。
- **G1**（freeze criteria 数量闸）：scoped-reopen 已分担 cap 压力，数量闸误伤合理大改造。改为 freeze 时 warning 即可，但优先级低于 E1。

---

## 5. 对抗性审查（self-review of the plan）

### R1（对 J2 option A）：严格禁止 manual+reproducible 过严

**反驳**：judgment evidence 常常是「人工判断 + artifact 存在性」混合。例如「截图改善（人看）+ 截图文件存在（可复现 `ls`）」。option A 一刀切禁 reproducible，连 artifact 存在性校验也丢了——反而**降低**了 evidence 的可机检部分。
**修订**：提供 **option B**——不禁 reproducible，而是要求 manual+reproducible 时必须带显式声明字段：
```yaml
sensor_scope: artifact_existence_only   # 新字段：sensor 只验 artifact，不验判断
residual_risk:
  level: low
  notes: "视觉判断部分为 manual observation，未经 sensor 验证"
```
schema 校验：`manual + reproducible + 缺 sensor_scope/artifact 声明 → 拒绝`。这样既保留 artifact 校验，又强制显式承认判断部分不可机检。
**结论**：J2 推荐 option B（更精确，但多一个字段）；option A 作为更简单的备选。两者都堵住了 P2-002 那种「不声明就伪装」的漏洞。**J2 仍属必做，但实现选 B**。

### R2（对 V1）：history 推断的边缘情况

**反驳**：① 并发 close 两进程同时扫 history 可能撞号；② 跨 worktree 时 history/ 不同步；③ history 目录名不规范（非 v####）。
**评估**：① close 本身不是为并发设计（state.yaml 单写），无需处理；② 跨 worktree 是 goalspec 已有的更广问题，不归 V1；③ 正则 `^[0-9]+$ ` 已过滤非数字目录名。
**结论**：V1 方案稳健，warning 是关键（让人类看见推断发生）。维持必做。

### R3（对 E1）：draft 会不会变成新的仪式负担？

**反驳**：从「手算 hash + heredoc」变成「draft + 编辑 reason + apply」，仍是两步。是否真省？
**评估**：省的关键是 **hash 自动算**（消灭 6m+ 的源码摸索与手抄）与 **schema 骨架内置**（消灭 YAML 解析错误与缺 token 返工）。这两项是日志里实测的最大耗时。两步 vs 三步（draft/edit/apply）但每步零猜测，净收益明确。
**进一步反驳**：Master 会不会拿到 draft 骨架后直接 apply 不补 reason？——不会，因为 apply 的 reason 仍 grep 5 token，TODO 占位会被拒。draft 骨架的 TODO 强制 Master 填实质内容。
**结论**：E1 维持高杠杆推荐。重构抽出 `validate_inputs` 是 nice-to-have，不阻塞。

### R4（对 A1）：默认值问题是哲学，代码解不了

**反驳**：无论 `enforce_on_all_soft` 默认 true/false 都有问题（R4 本身已承认）。这是 advice-vs-gap 在 fidelity 层的重演——加开关不等于堵漏洞，项目不开启就是装饰。
**评估**：完全成立。A1 的真正价值不在「新增 block 能力」（框架已有 opt-in），而在 **discoverability**——让无 profile 项目知道自己零客观门禁。
**修订**：A1 的核心交付物改为 **init/profile 生成时的显式 warning**（无 smoke_tests → profile 顶部写 WARNING 注释 + status 命令红字提示），而非默认 block。block 能力仍加（供项目自觉开启），但**不指望默认值拯救**。
**结论**：A1 从「堵漏洞」降级为「让漏洞可见」。这与第 6 节对抗审查的结论一致（advisory 不进门禁是哲学）。若框架定位不变，A1 的 block 部分甚至可砍，只留 discoverability。

### R5（对 S1）：缓存引入新故障源，不值

**反驳**：sensor 的价值就是「此刻 command 真退出 0」。缓存文件是新增状态，有被污染/过期/并发写的风险；close 终检清理依赖流程完整（close 失败则缓存残留）。收益（省 vitest 重跑）在 J2 之后，因为 J2 会让一部分慢 evidence 标 reproducible=false（不再进 sensor）。
**修订**：**S1 推迟，先做 J2**。若 J2 之后 F4 痛感仍显著，再考虑 S1，且限定缓存范围为「单次 close 周期 + contract_hash 不变」，close 终检强制 fresh。
**结论**：S1 移出 MVP。

### R6（对 F6）：suggest 粒度收窄可能淹没用户

**反驳**：未归属文件多时（如装一个包带 10 个 lock 子文件），文件级建议会刷屏。
**修订**：F6 改为「**精确文件 + 顶层 glob 双建议**」，并在 amend 命令提示 `--allow <exact-file>` 优于 `--allow dir/**`。
**结论**：F6 维持低优先、低成本，可顺手做。

### R7（整体）：6 个改动是否过度？

**反驳**：CLAUDE.md「简单优先」——一个 87-criteria 的单例复盘，推导出 6 个框架改动，是否 overfit？
**评估**：F1/F5/F7 是源码铁证（非归纳），J2/V1 必做。E1 是实测最大耗时杠杆。A1 受哲学约束。S1/F6 可推迟。**MVP 应只含 J2 + V1 + E1**。
**结论**：MVP 收敛为 3 项。

---

## 6. 推荐落地（审查后定稿）

### MVP（立即可做，零/低反效果）
1. **J2 (option B)**：`lib/schema.sh` 加 `manual+reproducible→须 sensor_scope 声明` 校验。
2. **V1**：`lib/close.sh` next_history_version 加 history fallback + warning。
3. **E1**：`commands/judge.sh` 加 `draft` 子命令（自动 hash + 骨架）。

→ 验证：各构造一条触发 case，确认 `evidence check` / `close` / `judge draft→apply` 行为正确，且无 profile / 旧 verdict 仍工作。

### 次轮（需决策，非纯工程）
4. **A1 (discoverability 版)**：`init` / `status` 在无 smoke 时显式 WARNING；block 开关作为 opt-in 提供，**默认值留给框架作者定夺**（见 R4）。

### 推迟（看痛感）
5. **S1 / F6**：J2 之后若 F4 仍痛做 S1；F6 顺手。

### 不做
6. **J1 / G1**：反效果高于收益。

---

## 7. 一句话方案

**先做 J2 + V1 + E1 三件**——它们堵住了 P2-002 式客观假象、修了版本号静默重置、消灭了手算 hash 的最大仪式开销，且都是几行到几十行、零兼容性破坏的改动。A1 的 all-soft 堵漏本质是设计哲学选择（默认值 vs discoverability），代码改动只是它的载体，决策权在框架定位，不在本方案。
