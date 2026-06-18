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

Follow `NEXT_ACTION`, `ROLE`, `READ`, `MAY_EDIT`, `MUST_NOT_EDIT`, `BLOCKERS`, and `CURRENT_WORK_UNIT`.

Do not start a goal from casual discussion. Start intake only after explicit human authorization.

## User Commands

Treat user-facing commands as shorthand:

- `/goalspec status` -> run `.goalspec/goalspec status`.
- `/goalspec begin <intent>` -> run `.goalspec/goalspec intake begin "<intent>"`.
- `/goalspec source <path>` -> run `.goalspec/goalspec intake add-source <path>`.
- `/goalspec end` -> run `.goalspec/goalspec intake end`, then write `intake-capture.md` and `constraint-suggestions.yaml`.
- `确认` after package review -> run `.goalspec/goalspec approve intake-package`, then `.goalspec/goalspec intake apply-suggestions`.
- `/goalspec next` or "继续" -> run status and execute only the current `NEXT_ACTION`.

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
- Never self-certify completion. Completion requires guardian verdicts and `.goalspec/goalspec complete`.
