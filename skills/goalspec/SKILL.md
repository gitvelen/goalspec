---
name: goalspec
description: Use when working in a project with .goalspec/ or when the user asks to start, capture, constrain, compile, execute, judge, close, reopen, or complete a Goalspec-managed project change.
---

# Goalspec

Goalspec is project-local and explicit opt-in. The source of truth is the project's `.goalspec/`, not this skill or chat.

Only enter the Goalspec lifecycle when the human explicitly uses a `/goalspec ...` command or clearly asks to run a formal Goalspec change. Otherwise, handle the request as normal development work; you may suggest Goalspec for larger or riskier changes, but do not self-upgrade casual requests into this workflow.

## The three core actions

```text
/goalspec start <intent>   begin defining a change
/goalspec run              begin implementation and verification; generate a close package when Criteria pass
/goalspec close            close out: apply memory, archive, and configured delivery
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

Treat user-facing commands as the human interface; run the project-local CLI only as the agent execution translation:

- `/goalspec status` -> run `.goalspec/goalspec status`.
- `/goalspec start <intent>` -> run status first; only continue with `.goalspec/goalspec start "<intent>"` when state is `no_goal` or `closed`.
- `/goalspec source <path>` -> run `.goalspec/goalspec source <path>`.
- `/goalspec end` -> run `.goalspec/goalspec end`, then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review, show them to the human, and wait for explicit confirmation before freezing.
- `确认并应用 intake package` after package review -> run `.goalspec/goalspec approve intake-package`, then `.goalspec/goalspec intake apply-suggestions`.
- `确认并冻结契约` after Goal/Criteria/Constraints review -> freeze the reviewed artifacts and stop. Do not implement.
- `/goalspec run` -> run `.goalspec/goalspec run`, read the full Goal-Driven Prompt before modifying business code, and execute that prompt.
- `/goalspec close` -> run `.goalspec/goalspec close`; do not manually replace it with archive/git/push/PR/state edits.
- `继续` -> run status. Do not begin implementation unless the user explicitly includes `/goalspec run`. Do not close unless the user explicitly includes `/goalspec close`.
- Bare `确认` / `ok` / silence -> not enough for approval; require the stage-specific phrases above.
- Requests that do not explicitly enter Goalspec -> answer or implement normally; do not run `.goalspec/goalspec ...` commands unless the human explicitly opts in.

For complete command mapping, read `references/command-map.md`.

`start`, `end`, `run`, and `close` are human gates: run the underlying CLI ONLY when the user issues the matching `/goalspec` command — never self-initiate (e.g. do not run `intake end` because the intent looks captured; draft the package and stop, and wait for `/goalspec end`).

## Intake Package

After intake ends, write both and show a concise review summary (Goal summary, sources, suggested constraints, blockers):

```text
.goalspec/active/intake-capture.md
.goalspec/active/constraint-suggestions.yaml
```

Use `references/constraint-extraction.md` for extraction rules. Show both files to the human and wait for explicit confirmation or corrections before approving/applying. Never write `.goalspec/project/**` before the package is approved and applied.

## Criteria Drafting

When compiling the contract (`goalspec compile`), draft Criteria using `references/criteria-writing.md`. It is a five-step authoring procedure whose main thread is product-perspective coverage: every goal branch in `goal.md` (Intent, Narratives, every Success Model field, Scope, Risk Scan) must trace to at least one Criterion, each `must_not_happen` becomes a negative Criterion, and the `final_completion_signal` becomes the single `final: true` Criterion. The procedure then applies an engineering-validity lens, a testing-coverage lens, and a verifiability / loop-safety lens so every Criterion is decidable into a clear pass/fail and the run-loop can converge rather than stall.

## Reopen Policy

`/goalspec reopen <reason>` is for frozen Goal / Criteria / Constraints problems, not ordinary unfinished implementation.

After reopen:
- explain why the frozen contract is wrong, insufficient, or conflicting;
- complete `.goalspec/active/reopen-impact.yaml` with a Criteria-level impact analysis and blocking questions for human review;
- treat the previous frozen contract as demoted back to `draft`, then re-review, re-approve, and re-freeze before `/goalspec run` may resume;
- do not keep implementing, judging, or closing against the old basis.

Reopen does not mean "redo everything". The framework records completion at the Criteria/evidence/verdict level, not as a task checklist. Reopen should drive impact analysis over Criteria (`unchanged`, `modified`, `added`, `removed`) and re-validation of the affected Criteria; only global Goal/Constraint changes justify full re-validation.

When a request adds a new improvement that does not change whether the current Goal is complete, prefer closing the current change and starting a new `/goalspec start <intent>` instead of reopening.

## Close Package

When `/goalspec run` reports `CLOSE_PACKAGE_READY: true`, show `.goalspec/active/close-package.yaml` or `.goalspec/active/close-package.md` to the human and wait for `/goalspec close`.

`/goalspec close` means the human confirms the current close package and authorizes memory patch application, history archive, and the configured delivery mode (for example GitHub PR, push-only, local commit, or archive-only). Close is recoverable: if it fails, re-running continues from the checkpoint.

## Verdict Discipline

A `pass` verdict means the Criteria statement is semantically covered, not merely that evidence_requirement_refs are present.

Before any `pass`, the Master must perform a Criteria Coverage Audit:

- decompose the criterion statement into atomic claims;
- map each claim to supporting evidence ids;
- classify evidence strength (real runtime, browser runtime, API runtime, integration test, unit test, fixture, mock, static assertion, manual observation);
- check whether the evidence strength is sufficient for the claim;
- emit `insufficient` / `fail` / `blocked` / `stale` / `reopen_required` if any claim is uncovered or weakly covered.

Pass verdict reasons must contain `Coverage audit:` plus claim/evidence/sufficiency/conclusion details. Judgment Criteria require extra skepticism: check whether evidence is real runtime vs fixture/mock, whether failure states and samples are covered, and whether missing-state evidence is being incorrectly used as full-data proof.

If the human asks whether something was actually observed or proven, answer from Criteria claims and evidence contents. Do not cite an existing pass verdict as self-proof.

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
- Only cite `reproducible: true` evidence whose `command` genuinely re-passes — the sensor re-runs it at `judge apply` and rejects the verdict on a failing re-run. Mark side-effecting evidence `reproducible: false`. For the full evidence field guide (fields, runtime_boundary matching, the reproducible/side-effect/flaky rules Subagents follow when producing evidence), see `references/evidence-writing.md`.
- Treat `.goalspec/active/harness-improvement-candidate.yaml` (emitted on `capped`/`stalled`) as advisory. Never fill `proposed_target`/`prediction` or set `promoted: true` automatically — promotion is human-gated.
