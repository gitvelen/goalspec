<!-- GOALSPEC:BEGIN -->
# Goalspec

This project uses Goalspec. The project-local `.goalspec/` directory is the source of truth; this managed block is only a thin operating guide for Goalspec-managed work.

## Scope And Priority

Goalspec is explicit opt-in. Only enter this lifecycle when the human explicitly uses `/goalspec ...` or clearly asks to run a formal Goalspec-managed change. Otherwise, handle the request as normal development work, follow the project's ordinary guidance, do not run `.goalspec/goalspec ...`, and do not self-upgrade casual requests into this workflow.

When a request is Goalspec-managed, this block governs the Goalspec gates. For detailed role rules, read `.goalspec/ai/core.md`; do not execute from memory.

## Start Here

Before Goalspec-managed work, run or read:

```bash
.goalspec/goalspec status
```

Follow `STATE`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and especially `NEXT_USER_ACTION`.

Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## Human Command Map

Human-facing commands are translated mechanically. Agent CLI translation is allowed only for the matching human input below.

| Human input | Agent CLI translation | Stop point |
| --- | --- | --- |
| `/goalspec status` | `.goalspec/goalspec status` | Report state and `NEXT_USER_ACTION`. |
| `/goalspec start <intent>` | Run status first, then `.goalspec/goalspec start "<intent>"` only from `no_goal` or `closed`. | Intake is open; do not implement. |
| `/goalspec source <path>` | `.goalspec/goalspec source <path>` | Source is added; do not close intake. |
| `/goalspec end` | `.goalspec/goalspec end` | Draft and show the review package; wait for stage-specific confirmation. |
| `确认并应用 intake package` | `.goalspec/goalspec approve intake-package`, then `.goalspec/goalspec intake apply-suggestions` | Stop after applying confirmed suggestions. |
| `确认并冻结契约` | Run only the status-required review, approval, and freeze commands for the reviewed Goal/Criteria/Constraints. | Stop after `.goalspec/active/goal-driven-prompt.md` is generated; do not implement. |
| `/goalspec run` | `.goalspec/goalspec run` | If allowed, read the full prompt before business-code edits; if a close package is ready, show it and stop. |
| `/goalspec close` | `.goalspec/goalspec close` | Report success or the CLI blocker; never replace close manually. |
| `/goalspec reopen <reason>` | `.goalspec/goalspec reopen <reason>` | Draft impact and revised contract material; wait for re-review and re-freeze. |

`/goalspec next` is not part of the goal-driven command surface.

## Hard Gates

`start`, `end`, `run`, and `close` are human gates. Execute the matching `.goalspec/goalspec <cmd>` only when the human issues the exact slash-command; never self-initiate them.

- Do not run `goalspec intake end` or `.goalspec/goalspec intake end` because the intent looks captured.
- Do not run `/goalspec run` or `.goalspec/goalspec run` because Criteria look satisfiable.
- Do not run `/goalspec close` or `.goalspec/goalspec close` because a close package exists.
- Bare "确认", "继续", "ok", or silence is not permission to implement, freeze, or close. `继续` means run status and report the next action unless it explicitly includes `/goalspec run` or `/goalspec close`.

## Intake And Freeze

During intake, capture conversation, ask only Goal/Criteria/Constraints/scope/risk/user-visible behavior questions, and add approved sources. Do not freeze artifacts, generate the Goal-Driven Prompt, modify business code, or decide intake is finished.

After `/goalspec end`, generate and show a concise review package from `.goalspec/active/intake-conversation.md`, `.goalspec/active/intake-sources.yaml`, approved source snapshots, `.goalspec/active/intake-capture.md`, and `.goalspec/active/constraint-suggestions.yaml`:

- Goal summary
- source material used
- required Criteria
- hard Constraints plus allowed/forbidden paths
- out-of-scope
- blocking questions
- suggested project/profile changes

Before writing `.goalspec/project/**` from suggestions, require `确认并应用 intake package`. Before freezing the reviewed Goal/Criteria/Constraints, require `确认并冻结契约`. Confirmation never starts implementation.

## Criteria Review Minimum

For every required Criterion shown to the human, include:

- `failure means incomplete`: why failing this item means the Goal is not done.
- `observable result`: the behavior or state the Master can inspect.
- `evidence path`: the evidence requirement or runtime boundary that can prove it.

Keep required Criteria clear, decidable from evidence, Goal-relevant, and minimal. Move nice-to-have items to `optional_criteria`. Move execution boundaries to Constraints. Do not write implementation steps, file paths, technologies, internal tasks, or test commands as success standards unless the human explicitly makes them part of the Goal.

## Run, Reopen, Close

When `/goalspec run` is explicitly requested, run `.goalspec/goalspec run`. If it prints `GOALSPEC_RUN_ALLOWED: false`, stop and report the blocker. If it is allowed, read `.goalspec/active/goal-driven-prompt.md` in full before modifying business code, then follow that prompt's frozen Goal, Criteria, and Constraints.

The Subagent may produce evidence, but cannot declare final success. Only Master verdicts with `evaluated_by: master` can judge Criteria. Passing tests, Subagent self-reports, and evidence text are not closure.

If the run-loop is capped, stalled, blocked by judgment-kind Criteria, or reports a stale/missing prompt, stop and report status' `NEXT_USER_ACTION`. Do not retry blindly.

Use reopen only when the frozen Goal, Criteria, or Constraints are wrong, insufficient, contradictory, or newly conflict with the human's intended acceptance basis. Do not keep implementing, judging, or closing against an invalid frozen basis.

Close only through `.goalspec/goalspec close` after the human runs `/goalspec close`. Do not manually replace it with git, push, PR, archive, state edits, or direct `status: closed` writes. Closure requires all required Criteria to have fresh Master pass verdicts, Constraints to remain respected, a current close package, final verification, and the configured delivery mode.

<!-- GOALSPEC:END -->
