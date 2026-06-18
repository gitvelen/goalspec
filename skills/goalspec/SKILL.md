---
name: goalspec
description: Use when working in a project with .goalspec/ or when the user asks to start, capture, constrain, compile, execute, judge, reopen, or complete a Goalspec-managed project change.
---

# Goalspec

Goalspec is project-local. The source of truth is the project's `.goalspec/`, not this skill or chat.

## First Step

When a project contains `.goalspec/`, run:

```bash
.goalspec/goalspec status
```

Follow `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and `NEXT_USER_ACTION`.

Do not start a goal from casual discussion. Start intake only after explicit human authorization.

## User Commands

Treat user-facing commands as shorthand:

- `/goalspec status` -> run `.goalspec/goalspec status`.
- `/goalspec start <intent>` -> run `.goalspec/goalspec start "<intent>"`.
- `/goalspec source <path>` -> run `.goalspec/goalspec source <path>`.
- `/goalspec end` -> run `.goalspec/goalspec end`, then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review.
- `确认` after package review -> run `.goalspec/goalspec approve intake-package`, then `.goalspec/goalspec intake apply-suggestions`.
- `确认` after Goal/Criteria/Constraints review -> freeze the reviewed artifacts and stop. Do not implement.
- `/goalspec run` -> run `.goalspec/goalspec run`, read the full Goal-Driven Prompt before modifying business code, and execute that prompt.
- "继续" -> run status. Do not begin implementation unless the user explicitly includes `/goalspec run`.

For complete command mapping, read `references/command-map.md`.

## Intake Package

After intake ends, write both:

```text
.goalspec/active/intake-capture.md
.goalspec/active/constraint-suggestions.yaml
```

Use `references/constraint-extraction.md` for extraction rules. Show both files to the human and wait for explicit confirmation or corrections before approving/applying. Never write `.goalspec/project/**` before the package is approved and applied.

## Hard Rules

- Never write business code during intake or compile.
- Never write `goal.md` from unapproved conversation capture.
- Never write `project/**` directly from unconfirmed suggestions.
- Never treat implementation steps as goal or project constraints unless the human explicitly confirms them as constraints.
- Never treat confirmation as run permission.
- Never modify business code before reading `.goalspec/active/goal-driven-prompt.md` in full after an allowed `/goalspec run`.
- If `.goalspec/goalspec run` prints `GOALSPEC_RUN_ALLOWED: false`, stop.
- Never self-certify completion. Completion requires Master/Guardian verdicts and `.goalspec/goalspec complete`.
