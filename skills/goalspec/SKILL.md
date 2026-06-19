---
name: goalspec
description: Use when working in a project with .goalspec/ or when the user asks to start, capture, constrain, compile, execute, judge, close, reopen, or complete a Goalspec-managed project change.
---

# Goalspec

Goalspec is project-local. The source of truth is the project's `.goalspec/`, not this skill or chat.

## The three core actions

```text
/goalspec start <intent>   begin defining a change
/goalspec run              begin implementation and verification; generate a close package when Criteria pass
/goalspec close            close out: apply memory, archive, commit, push, open a PR
```

Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## First Step

When a project contains `.goalspec/`, run:

```bash
.goalspec/goalspec status
```

Follow `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and `NEXT_USER_ACTION`.

Do not start a goal from casual discussion. Start intake only after explicit human authorization, and only when state is `no_goal` or `closed`.

## User Commands

Treat user-facing commands as shorthand:

- `/goalspec status` -> run `.goalspec/goalspec status`.
- `/goalspec start <intent>` -> run status first; only continue with `.goalspec/goalspec start "<intent>"` when state is `no_goal` or `closed`.
- `/goalspec source <path>` -> run `.goalspec/goalspec source <path>`.
- `/goalspec end` -> run `.goalspec/goalspec end`, then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review.
- `确认` after package review -> run `.goalspec/goalspec approve intake-package`, then `.goalspec/goalspec intake apply-suggestions`.
- `确认` after Goal/Criteria/Constraints review -> freeze the reviewed artifacts and stop. Do not implement.
- `/goalspec run` -> run `.goalspec/goalspec run`, read the full Goal-Driven Prompt before modifying business code, and execute that prompt.
- `/goalspec close` -> run `.goalspec/goalspec close`; do not manually replace it with archive/git/push/PR/state edits.
- `继续` -> run status. Do not begin implementation unless the user explicitly includes `/goalspec run`. Do not close unless the user explicitly includes `/goalspec close`.

For complete command mapping, read `references/command-map.md`.

## Intake Package

After intake ends, write both:

```text
.goalspec/active/intake-capture.md
.goalspec/active/constraint-suggestions.yaml
```

Use `references/constraint-extraction.md` for extraction rules. Show both files to the human and wait for explicit confirmation or corrections before approving/applying. Never write `.goalspec/project/**` before the package is approved and applied.

## Close Package

When `/goalspec run` reports `CLOSE_PACKAGE_READY: true`, show `.goalspec/active/close-package.yaml` or `.goalspec/active/close-package.md` to the human and wait for `/goalspec close`.

`/goalspec close` means the human confirms the current close package and authorizes memory patch application, history archive, commit, push, PR creation, and delivery metadata. Close is recoverable: if it fails, re-running continues from the checkpoint.

## Hard Rules

- Never write business code during intake or compile.
- Never write `goal.md` from unapproved conversation capture.
- Never write `project/**` directly from unconfirmed suggestions.
- Never treat implementation steps as goal or project constraints unless the human explicitly confirms them as constraints.
- Never treat confirmation as run permission.
- Never modify business code before reading `.goalspec/active/goal-driven-prompt.md` in full after an allowed `/goalspec run`.
- If `.goalspec/goalspec run` prints `GOALSPEC_RUN_ALLOWED: false`, stop.
- Never self-certify completion. Criteria completion requires Master verdicts; delivery closure requires `.goalspec/goalspec close`.
- Never manually substitute for `.goalspec/goalspec close` with git/gh/archive/state edits.
- Never directly write `status: closed`.
- Never start a new change unless status is `no_goal` or `closed`.
