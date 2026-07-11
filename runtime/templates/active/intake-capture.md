# Intake Capture

## Goal Candidate

## User-visible Success

## System-observable Success

## Acceptance Signals (验收点)

<!-- 与上面的 User-visible / System-observable Success 分开——那两节是「能力清单」（能做什么），
  本节是「验收点」（做到什么程度算成功）。每条必须满足：
  - 回答「做到什么程度算成功」，而非「能做 X」；
  - 是可判定的 done 条件——能描述 fail 长什么样（不通过时观测到什么）；
  - 「页面可加载」「能展示 X」「三页无报错」这类只证存在、不证成功的，算弱验收点，要收紧。
  效用/统计类（如「回测能否支撑投产判断」「因子 IC 是否有预测力」）允许定性，但必须显式列出，
  并在下游 contract 对应 criterion 标 kind: judgment（不强转 machine）。
  边界：验收点是「AI 已正确理解的设计不变量」的可判定投影；挡不住「AI 设计模型本身错」
  （那需设计阶段或人类领域审查），只防实现期偏离已确认的成功口径。 -->

## Scope

## Confirmed Decisions

<!-- 每条决策必须标注 provenance，便于 intake-capture 对抗审查机械核对「用户明示」与「AI 默认/推断」：
  - [user_said] <决策> 「<用户原话引文>」  // 必须附 verbatim 引文（能 grep 命中 intake-conversation.md，
                                           //   且是用户发起的决策，非「你看着办/都行」类授权话、
                                           //   非「同意 AI 建议」）
  - [assistant_defaulted] <决策>            // AI 给的默认，用户未明确反对
  - [inferred] <决策>                       // AI 从代码/上下文推断
  规则：引不到用户原话的，不得标 [user_said]——降级为 [assistant_defaulted]/[inferred]。
  影响 goal/scope/实现方向的 assistant_defaulted/inferred 应进 Open Questions，而非此段。
  对抗审查会机械核对每条 [user_said] 的引文是否真在对话里出现、是否用户发起；引文缺失/不匹配 = blocking。
  可选 [DEC-NNN] id 仅用于人读追溯，不强制。 -->

## Open Questions

## Excluded / Not Yet Confirmed

