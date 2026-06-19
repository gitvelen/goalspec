# Goalspec

Goalspec is a project-local Goal-Driven Prompt framework for AI-assisted development.
It keeps the AI from drifting into task-list execution: the AI executes only a frozen Goal-Driven Prompt, and a change is only closed through the project-local CLI.

The public model has four artifacts:

- `Goal` — what the user wants to achieve.
- `Criteria` — required success standards used by the Master Agent to judge completion.
- `Constraints` — boundaries the AI must not violate.
- `Close Package` — the reviewed delivery package generated after all required Criteria pass.

## The three core actions

Users only need three actions:

```text
/goalspec start <intent>   begin defining a change
/goalspec run              begin implementation and verification; generate a close package when Criteria pass
/goalspec close            close out: apply memory, archive, commit, push, open a PR
```

The single rule that decides whether a change is done:

> Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## Install

```bash
cd /path/to/project
git init                  # if the project is not already a git repo
/path/to/goalspec init
```

This creates `.goalspec/` and installs managed Goalspec blocks into `AGENTS.md` and `CLAUDE.md`.

Optional AI adapter install:

```bash
/path/to/goalspec install-ai codex    # or claude / lingma
```

## User commands

Use only these user-facing commands:

```text
/goalspec start <intent>
/goalspec source <path>
/goalspec end
/goalspec run
/goalspec close
/goalspec status
/goalspec reopen <reason>
```

`/goalspec run` is the only implementation entry. `/goalspec close` is the only closure entry.
`继续` does not begin implementation unless it explicitly includes `/goalspec run`, and does not close unless it explicitly includes `/goalspec close`.

## Lifecycle

```text
no_goal
  -> intake_collecting
  -> spec_drafting
  -> awaiting_human_confirmation
  -> ready_to_run
  -> running
  -> ready_to_close
  -> closing
  -> closed
```

Recovery states: `blocked`, `reopen_required`.

- `ready_to_run` — Goal, Criteria, Constraints are frozen and the Goal-Driven Prompt is fresh. Run `/goalspec run`.
- `running` — the AI executes the frozen Goal-Driven Prompt. Judging and continuing happen internally as a Master/Subagent loop.
- `ready_to_close` — all required Criteria have fresh Master pass verdicts and a close package has been generated. Review it, then run `/goalspec close`.
- `closing` — `/goalspec close` is in progress or recoverable. Re-run `/goalspec close` to continue from the checkpoint.
- `closed` — the change is fully closed. Only this state allows the next `/goalspec start <intent>`.

## Workflow

1. `/goalspec start <intent>` opens a formal intake window.
2. `/goalspec source <path>` adds files or directories while intake is open.
3. `/goalspec end` closes intake. The AI then drafts Goal, Criteria, Constraints, out-of-scope, and blocking questions for human review.
4. Human confirmation freezes the reviewed Goal, Criteria, and Constraints and generates `.goalspec/active/goal-driven-prompt.md`. Confirmation does not start implementation.
5. `/goalspec run` begins implementation.
6. After all required Criteria have fresh Master pass verdicts, `/goalspec run` generates `.goalspec/active/close-package.yaml` and enters `ready_to_close`.
7. `/goalspec close` confirms the current close package and performs delivery.

## Run gate

`/goalspec run` refuses execution unless all preconditions pass:

- Goal, Criteria, and Constraints are frozen.
- No blocking questions remain.
- The Goal-Driven Prompt exists.
- Frozen artifact hashes and prompt hash are current.

Allowed run output:

```text
GOALSPEC_RUN_ALLOWED: true
PROMPT_FILE: .goalspec/active/goal-driven-prompt.md
PROMPT_HASH: sha256:...
READ_THIS_PROMPT_FULLY_BEFORE_ACTION: true
```

When all required Criteria pass, run output instead reports:

```text
CLOSE_PACKAGE_READY: true
CLOSE_PACKAGE_FILE: .goalspec/active/close-package.yaml
CLOSE_PACKAGE_HASH: sha256:...
NEXT_USER_ACTION: Review the close package, then run /goalspec close to archive, commit, push, and open a PR.
```

Blocked run output includes `GOALSPEC_RUN_ALLOWED: false`, a `BLOCKER`, and `NEXT_USER_ACTION`.

## Close

`/goalspec close` is the only user-visible closure command. It confirms the current close package and authorizes the full delivery:

1. Validate the close package and recompute every bound hash (contract, evidence, verdict, memory-patch, changed-files, suggested delivery, close package).
2. Run final verification (test/build/lint/typecheck from `.goalspec/project/profile.yaml`).
3. Scan for secrets, large files, and disallowed temp files.
4. Re-run scope-check.
5. Apply the memory patch to `.goalspec/project/**`.
6. Archive active files to `.goalspec/history/vNNNN/` and update `project/versions.yaml`.
7. Create or reuse a delivery branch `goalspec/<goal-id>-<slug>`.
8. Create the main commit, push, open a PR, then a metadata commit recording the PR URL and delivery facts.
9. Enter `closed`.

Close is recoverable. If it fails mid-way it stops at a checkpoint; re-running `/goalspec close` continues from there without repeating the main commit. A stale close package (any bound hash changed since generation) is rejected — re-run `/goalspec run` to regenerate it.

AI tools must not replace `/goalspec close` with manual `git add`, `git commit`, `git push`, `gh pr create`, archive, or `status: closed` edits. On failure, report the CLI's blocker and next user action.

Close does not auto-merge the PR, create releases, tag versions, or deploy. Those are out of scope.

## Execution model

The generated prompt defines one Master Agent and one Subagent.

- The Subagent works toward the frozen Goal under the frozen Constraints.
- The Master Agent evaluates progress strictly against the frozen Criteria.
- Internal attempts, execution scopes, test runs, and implementation steps are not success standards.
- Criteria satisfaction is the only success condition.
- If Goal, Criteria, or Constraints appear wrong during execution, stop and request `/goalspec reopen <reason>`.

If an AI tool does not support explicit subagents, it must visibly simulate:

```text
Master Evaluation
Subagent Work
Evidence/Progress Report
Master Evaluation
```

## Criteria

All entries under `criteria:` are required by default. Do not add repetitive `required: true` fields.

Use `optional_criteria:` for useful ideas that should not block closure.

Each required criterion must be:

- clear;
- decidable from evidence;
- relevant to the Goal;
- minimal, without implementation steps or technology choices.

## Evidence, verdict, close

Evidence records observable facts and binds them to Criteria. The Subagent may produce evidence.

Only the Master Agent may produce final verdicts. A Subagent's self-report, passing tests, or evidence text cannot close the goal.

Closure requires all required Criteria to have fresh pass verdicts, Constraints to remain respected, a current `.goalspec/active/close-package.yaml`, final verification to pass, and `.goalspec/goalspec close` to complete delivery.

## Status

Run status whenever unsure:

```bash
.goalspec/goalspec status
```

It reports `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `UNMET_CRITERIA`, and `NEXT_USER_ACTION`.
