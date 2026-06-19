<!-- GOALSPEC:BEGIN -->
# Goalspec

This project uses Goalspec. The project-local `.goalspec/` directory is the source of truth; this managed block is only the AI operating guide.

## The three core actions

```text
/goalspec start <intent>   begin defining a change
/goalspec run              begin implementation and verification; generate a close package when Criteria pass
/goalspec close            close out: apply memory, archive, commit, push, open a PR
```

Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## Start Here

1. Run or read `.goalspec/goalspec status` before Goalspec-managed work.
2. Follow `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and `NEXT_USER_ACTION`.
3. If role or prompt details are needed, read `.goalspec/ai/core.md`.
4. Do not start a goal from casual discussion. Enter intake only when the human explicitly asks to start/capture a Goalspec change, and only when state is `no_goal` or `closed`.
5. Do not modify business code during intake, drafting, review, confirmation, or prompt generation.

## User Commands

User-facing commands are:

- `.goalspec/goalspec start "<intent>"` — open the formal intake window (only from `no_goal` or `closed`).
- `.goalspec/goalspec source <path>` — add source material while intake is open.
- `.goalspec/goalspec end` — close intake; then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review.
- Human confirmation freezes the reviewed Goal, Criteria, and Constraints and generates `.goalspec/active/goal-driven-prompt.md`; it does not start implementation.
- `.goalspec/goalspec run` — the only implementation entry.
- `.goalspec/goalspec close` — the only closure entry after the close package is ready.
- `.goalspec/goalspec status` — inspect state.
- `.goalspec/goalspec reopen <reason>` — request human-approved changes when frozen artifacts are wrong or insufficient.

Do not treat "确认" or "继续" as permission to implement unless the human explicitly includes `/goalspec run`.
Do not close unless the human explicitly includes `/goalspec close`.
`/goalspec next` is not part of the goal-driven command surface.

## Intake Rules

During an open intake window, you may capture conversation, ask clarifying questions, and add approved source material.

Before `/goalspec end`, you must not freeze artifacts, generate the Goal-Driven Prompt, modify business code, or decide that intake is finished by yourself.

After `/goalspec end`, draft the review package from `.goalspec/active/intake-conversation.md`, `.goalspec/active/intake-sources.yaml`, `.goalspec/active/intake-capture.md`, `.goalspec/active/constraint-suggestions.yaml`, and any source snapshots. Show the human:

- Goal
- required Criteria
- Constraints
- out-of-scope items
- blocking questions

Before writing `.goalspec/project/**` from intake suggestions, get explicit human approval of the intake package, then run:

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

If the tool supports explicit subagents, create exactly one Subagent to execute. Otherwise simulate role separation with visible `Master Evaluation`, `Subagent Work`, and `Evidence/Progress Report` sections.

## Close Rules

The Subagent may produce evidence, but cannot declare final success.

Only Master verdicts with `evaluated_by: master` can judge Criteria. Passing tests, Subagent self-reports, and evidence text are not closure.

Closure requires all required Criteria to have fresh pass verdicts, Constraints to remain respected, a current `.goalspec/active/close-package.yaml`, final verification to pass, and `.goalspec/goalspec close` to complete delivery.

When the human explicitly requests `/goalspec close`:

1. Run `.goalspec/goalspec close`. Do not manually replace it with git, push, PR, archive, or state edits.
2. If it fails, report the blocker and next user action from the CLI; close is recoverable, so re-running continues from the checkpoint.
3. Do not directly write `status: closed`.
4. A stale close package is rejected — re-run `/goalspec run` to regenerate it.

Only `closed` permits starting another Goalspec change.

<!-- GOALSPEC:END -->
