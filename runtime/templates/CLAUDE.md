<!-- GOALSPEC:BEGIN -->
# Goalspec

This project uses Goalspec. The project-local `.goalspec/` directory is the source of truth; this managed block is only the AI operating guide.

Goalspec is explicit opt-in. Only enter this lifecycle when the human explicitly uses `/goalspec ...` or clearly asks to run a formal Goalspec-managed change. Otherwise, handle the request as normal development work; you may suggest Goalspec for larger or riskier changes, but do not self-upgrade casual requests into this workflow.

## The three core actions

```text
/goalspec start <intent>   begin defining a change
/goalspec run              begin implementation and verification; generate a close package when Criteria pass
/goalspec close            close out: apply memory, archive, and configured delivery
```

Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## Start Here

1. Run or read `.goalspec/goalspec status` before Goalspec-managed work.
2. Follow `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and `NEXT_USER_ACTION`.
3. If role or prompt details are needed, read `.goalspec/ai/core.md`.
4. Do not start a goal from casual discussion. Enter intake only when the human explicitly asks to start/capture a Goalspec change, and only when state is `no_goal` or `closed`.
5. Do not modify business code during intake, drafting, review, confirmation, or prompt generation.

## User Commands

Human-facing commands are:

- `/goalspec start <intent>` — open the formal intake window (only from `no_goal` or `closed`).
- `/goalspec source <path>` — add source material while intake is open.
- `/goalspec end` — close intake; then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review, show them to the human, and wait for `确认并冻结契约` before freezing.
- `确认并应用 intake package` — approve the reviewed intake package and apply its suggestions.
- `确认并冻结契约` — freeze the reviewed Goal, Criteria, and Constraints and generate `.goalspec/active/goal-driven-prompt.md`; it does not start implementation.
- `/goalspec run` — the only implementation entry.
- `/goalspec close` — the only closure entry after the close package is ready.
- `/goalspec status` — inspect state.
- `/goalspec reopen <reason>` — request human-approved changes when frozen artifacts are wrong or insufficient.

Agent CLI translation: execute `.goalspec/goalspec <cmd>` only as the mechanical translation of the corresponding human command above.
Do not treat bare "确认", "继续", "ok", or silence as permission to implement, freeze, or close. `继续` means run status and report the next action unless the human explicitly includes `/goalspec run` or `/goalspec close`.
`/goalspec next` is not part of the goal-driven command surface.

## Human-gated commands

`start`, `end`, `run`, and `close` are human gates. Execute `.goalspec/goalspec <cmd>` for these ONLY as a direct translation of the human's explicit slash-command. Never self-initiate them:

- Do not run `intake end` because the intent looks captured. Draft the intake package, show it, and STOP — the human types `/goalspec end`.
- Do not run `run` because Criteria look satisfied. Wait for `/goalspec run`.
- Do not run `close` because a close package exists. Wait for `/goalspec close`.

Bare "确认", "继续", "ok", or silence are NOT these slash-commands. Require stage-specific phrases such as `确认并应用 intake package` or `确认并冻结契约`.

## Intake Rules

During an open intake window, you may capture conversation, ask clarifying questions, and add approved source material.

Before `/goalspec end`, you must not freeze artifacts, generate the Goal-Driven Prompt, modify business code, or decide that intake is finished by yourself. In particular, do not execute `.goalspec/goalspec intake end` — only the human's `/goalspec end` closes the window.

After `/goalspec end`, draft the review package from `.goalspec/active/intake-conversation.md`, `.goalspec/active/intake-sources.yaml`, `.goalspec/active/intake-capture.md`, `.goalspec/active/constraint-suggestions.yaml`, and any source snapshots. Show a concise human review summary:

- Goal summary
- source material used
- required Criteria
- hard Constraints and allowed/forbidden paths
- suggested project/profile changes
- blocking questions

Before writing `.goalspec/project/**` from intake suggestions, get explicit human approval with `确认并应用 intake package`, then run:

```bash
.goalspec/goalspec approve intake-package
.goalspec/goalspec intake apply-suggestions
```

Ask only for decisions that affect Goal, Criteria, Constraints, scope, risk, or user-visible behavior. Do not ask ordinary implementation-detail questions.

## Run Hard Rules

When the human explicitly requests `/goalspec run`:

1. Run `.goalspec/goalspec run`.
2. If it prints `GOALSPEC_RUN_ALLOWED: false`, stop immediately and report the blocker and next user action.
3. If it prints `GOALSPEC_RUN_ALLOWED: true`, read `.goalspec/active/goal-driven-prompt.md` in full before modifying business code.
4. Treat the Prompt's Goal, Criteria, and Constraints as the authoritative execution instructions.
5. Do not substitute your own plan for the Prompt. Do not execute from memory.
6. If the Prompt is missing, stale, or not backed by frozen artifacts, do not continue.
7. If it prints `CLOSE_PACKAGE_READY: true`, show the close package and wait for explicit `/goalspec close`.
8. `/goalspec run` is a loop, not a single shot — once allowed, keep cycling Master Evaluation -> Subagent Work -> Evidence/Progress Report until the run-loop stops. The loop stops when: all required Criteria pass (the next `run` then generates the close package); the iteration cap is hit (`run_loop.last_outcome = capped`); no progress for several rounds (`stalled` — verdict fingerprint and evidence both unchanged); or only `judgment`-kind Criteria remain (those need human/Master resolution, not Subagent retry). If `run` or `judge apply` is denied as `capped` or `stalled`, stop and report `status`'s `NEXT_USER_ACTION` — `capped` means close-or-reopen, `stalled` means reopen (likely a spec defect). Do not retry blindly.

If the tool supports explicit subagents, create exactly one Subagent to execute. Otherwise simulate role separation with visible `Master Evaluation`, `Subagent Work`, and `Evidence/Progress Report` sections.

9. Evidence and observability: evidence with `reproducible: true` must carry a `command`; the sensor re-runs it at `judge apply` to confirm a pass — a failing re-run rejects the verdict, so only cite reproducible evidence that genuinely re-passes. Mark side-effecting evidence `reproducible: false`. On `capped`/`stalled`, Goalspec emits `.goalspec/active/harness-improvement-candidate.yaml` as advisory only; the framework never fills `proposed_target`/`prediction` and never auto-promotes — treat it as a signal to act on (likely reopen), not an action the AI takes by itself.

## Reopen Rules

Use `.goalspec/goalspec reopen <reason>` only when the frozen Goal, Criteria, or Constraints are wrong, insufficient, contradictory, or newly in conflict with the human's intended acceptance basis.

After reopen:
- explain the reopen reason and the impact on Goal / Criteria / Constraints;
- draft the contract changes and blocking questions for human review;
- re-review, re-approve, and re-freeze before any later `/goalspec run`;
- do not keep implementing, judging, or closing against the old frozen basis.

Reopen is not a synonym for "redo everything". Completion is tracked at the Criteria/evidence/verdict level, not as a task checklist. Reopen should drive impact analysis over affected Criteria (`unchanged`, `modified`, `added`, `removed`) and re-validation of the affected Criteria; only global Goal/Constraint changes justify full re-validation.

If the human asks for an additional improvement that does not change whether the current Goal is complete, prefer finishing the current change and starting a new `/goalspec start <intent>` instead of reopening.

## Close Rules

The Subagent may produce evidence, but cannot declare final success.

Only Master verdicts with `evaluated_by: master` can judge Criteria. Passing tests, Subagent self-reports, and evidence text are not closure.

Closure requires all required Criteria to have fresh pass verdicts, Constraints to remain respected, a current `.goalspec/active/close-package.yaml`, final verification to pass, and `.goalspec/goalspec close` to complete the configured delivery mode.

When the human explicitly requests `/goalspec close`:

1. Run `.goalspec/goalspec close`. Do not manually replace it with git, push, PR, archive, or state edits; the close package shows the configured delivery mode.
2. If it fails, report the blocker and next user action from the CLI; close is recoverable, so re-running continues from the checkpoint.
3. Do not directly write `status: closed`.
4. A stale close package is rejected — re-run `/goalspec run` to regenerate it.

Only `closed` permits starting another Goalspec change.

<!-- GOALSPEC:END -->
