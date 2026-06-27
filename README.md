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
/goalspec close            close out: apply memory, archive, and configured delivery
```

The single rule that decides whether a change is done:

> Only `closed` means the change is fully closed and another `/goalspec start <intent>` may begin.

## When Goalspec applies

Goalspec is explicit opt-in.

Use the Goalspec lifecycle only when the human explicitly does one of these:

- runs a `/goalspec ...` command;
- asks to start a formal Goalspec-managed change;
- asks to use the Goalspec workflow for this change.

Do not enter the lifecycle by default just because the repository contains `.goalspec/`.
Normal questions, debugging, small one-off edits, exploratory work, and casual discussion stay outside the lifecycle unless the human explicitly opts in.

AI tools may suggest Goalspec for larger or riskier changes, but must not silently upgrade ordinary requests into the Goalspec workflow.

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
/goalspec scope amend --allow <glob> --reason <text>
```

`/goalspec run` is the only implementation entry. `/goalspec close` is the only closure entry.
`继续` does not begin implementation unless it explicitly includes `/goalspec run`, and does not close unless it explicitly includes `/goalspec close`.

## Project development state diagram

The project development state diagram below is the canonical lifecycle map for a single Goalspec-managed change.
Use it to understand the main path, the human review gates, and the two recovery loops.

```text
                                   +----------------------+
                                   |       no_goal        |
                                   +----------+-----------+
                                              |
                                              | /goalspec start <intent>
                                              v
                                   +----------------------+
                                   |  intake_collecting   |
                                   +----------+-----------+
                                              |
                                              | /goalspec end
                                              v
                                   +----------------------+
                                   |    spec_drafting     |
                                   +----------+-----------+
                                              |
                                              | reviewed draft ready
                                              v
                             +----------------+----------------+
                             | awaiting_human_confirmation     |
                             +----------------+----------------+
                                              |
                                              | freeze
                                              v
                                   +----------------------+
                                   |     ready_to_run     |
                                   +----------+-----------+
                                              |
                                              | /goalspec run
                                              v
                                   +----------------------+
                                   |       running        |
                                   +----------+-----------+
                                              |
                                              | all required Criteria pass
                                              | and /goalspec run generates
                                              | close package
                                              v
                                   +----------------------+
                                   |   ready_to_close     |
                                   +----------+-----------+
                                              |
                                              | /goalspec close
                                              v
                                   +----------------------+
                                   |       closing        |
                                   +----------+-----------+
                                              |
                                              | delivery succeeds
                                              v
                                   +----------------------+
                                   |        closed        |
                                   +----------------------+

Recovery loops:

running -------------------------------> reopen_required
ready_to_close ------------------------/
reopen_required -- reopen-impact + re-review + re-approve + freeze --> ready_to_run

any state -----------------------------> blocked
blocked -------------------------------> lifecycle resumes after blocker resolution
```

## Lifecycle overview

Main lifecycle:

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

Recovery states:

```text
blocked
reopen_required
```

End-to-end flow with recovery loops:

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

running ---------> reopen_required --re-review / re-approve / freeze--> ready_to_run
ready_to_close --/

any state -------> blocked --------resolve blocker---------------------> lifecycle resumes
```

`reopen_required` is not a second implementation lane and not a shortcut back into intake. It is a contract re-review loop.

## Stage-by-stage reference

### `no_goal`

- Work: no active Goalspec change exists.
- Purpose: safe idle state.
- Human: may start a new formal change.
- AI: do not invent a goal from casual discussion.
- Allowed action: `/goalspec start <intent>`.
- Exit condition: explicit start.

### `intake_collecting`

- Work: capture intent and approved source material.
- Purpose: establish what problem is being defined before freezing anything.
- Human: continues clarifying intent, may add sources, eventually ends intake.
- AI: captures conversation and sources, but does not write business code or freeze artifacts.
- Allowed commands: `/goalspec source <path>`, `/goalspec end`.
- Exit condition: explicit `/goalspec end`.
- Prohibited: compile, freeze, run, close, business-code edits.

### `spec_drafting`

- Work: AI drafts Goal, Criteria, Constraints, out-of-scope, and blocking questions from the intake package.
- Purpose: turn the captured intent into a reviewable contract draft.
- Human: reviews the draft content.
- AI: must actively show the drafted Goal / Criteria / Constraints to the human for review.
- Allowed actions: review, revise, answer blocking questions, approve intake package, apply suggestions, compile.
- Exit condition: a reviewed contract draft advances to `awaiting_human_confirmation`.
- Prohibited: implementation.

### `awaiting_human_confirmation`

- Work: the draft Goal / Criteria / Constraints is waiting for explicit human confirmation.
- Purpose: freeze only human-confirmed acceptance criteria.
- Human: confirms or edits Goal / Criteria / Constraints.
- AI: incorporates review feedback, then waits for explicit confirmation before freezing.
- Allowed actions: review, approve, freeze.
- Exit condition: successful `freeze`.
- Prohibited: implementation.

### `ready_to_run`

- Work: Goal, Criteria, Constraints, and Prompt are frozen and fresh.
- Purpose: create a stable execution basis.
- Human: decides whether to begin implementation.
- AI: waits for explicit `/goalspec run`.
- Allowed command: `/goalspec run`.
- Exit condition: allowed run enters `running`.
- Prohibited: self-starting implementation.

### `running`

- Work: one Subagent implements; the Master judges Criteria against evidence.
- Purpose: reach fresh pass verdicts for all required Criteria.
- Human: may stop, clarify, or request reopen if the contract is wrong.
- AI: performs Master Evaluation -> Subagent Work -> Evidence/Progress Report loops.
- Allowed actions: implementation, evidence collection, Master verdicts.
- Exit condition:
  - all required Criteria fresh-pass -> next `/goalspec run` produces close package -> `ready_to_close`;
  - contract wrong/insufficient -> `/goalspec reopen <reason>` -> `reopen_required`.
- Prohibited: declaring completion without Master verdicts.

### `ready_to_close`

- Work: all required Criteria have fresh Master pass verdicts and a close package exists.
- Purpose: pause for human delivery review before outward-facing actions.
- Human: reviews the close package and decides whether to close.
- AI: shows the close package and waits.
- Allowed command: `/goalspec close`.
- Exit condition: explicit close enters `closing`.
- Prohibited: auto-close.

### `closing`

- Work: final verification, memory patch application, archive, and configured delivery metadata.
- Purpose: make delivery atomic and recoverable.
- Human: re-runs `/goalspec close` if recovery is needed.
- AI: reports blockers and checkpoint-based next action from the CLI.
- Allowed command: `/goalspec close` (resume).
- Exit condition: successful delivery enters `closed`.

### `closed`

- Work: the change is fully closed.
- Purpose: only state that permits the next formal change.
- Human: may start another change.
- AI: treats this as the only true done state.
- Allowed action: `/goalspec start <intent>`.

### `blocked`

- Work: progress is stopped by an external or operational blocker.
- Purpose: represent “the contract is still valid, but we cannot proceed yet”.
- Typical causes: broken environment, unavailable dependency, missing permission, failing external system.
- Human: resolves the blocker.
- AI: does not rewrite the contract; reports the blocker and waits.

### `reopen_required`

- Work: the frozen Goal / Criteria / Constraints is no longer acceptable.
- Purpose: invalidate the current frozen execution basis and force contract re-review.
- Typical causes: missing acceptance scenario, contradictory constraint, wrong goal framing, new human decision that changes what “done” means.
- Human: reviews the reopen impact, revises `goal.md` and/or `contract.yaml`, then re-reviews, re-approves, and freezes.
- AI: explains the reopen reason, drafts contract changes, and waits for human confirmation. It must not continue implementation, judging, or closing against the old basis.
- Exit condition: re-review / re-approve / `freeze` returns the change to `ready_to_run`.
- Prohibited: direct `/goalspec run`, `judge`, `complete`, or `close`.

## Workflow

1. `/goalspec start <intent>` opens a formal intake window.
2. `/goalspec source <path>` adds files or directories while intake is open.
3. `/goalspec end` closes intake.
4. After `/goalspec end`, the AI drafts a concise Goal / Criteria / Constraints review summary and waits for `确认并冻结契约`.
5. `确认并冻结契约` freezes the reviewed Goal, Criteria, and Constraints and generates `.goalspec/active/goal-driven-prompt.md`. Confirmation does not start implementation.
6. `/goalspec run` begins implementation.
7. After all required Criteria have fresh Master pass verdicts, `/goalspec run` generates `.goalspec/active/close-package.yaml` and enters `ready_to_close`.
8. `/goalspec close` confirms the current close package and performs delivery.

## Human review gates

`start`, `end`, `run`, and `close` are human-gated commands.

AI tools must execute the underlying CLI command only as a direct translation of the human's explicit `/goalspec ...` command:

- do not run `intake end` because the intent looks captured;
- do not run `run` because Criteria look satisfied;
- do not run `close` because a close package exists.

Normal “confirm”, bare “确认”, “continue”, “ok”, or silence are not substitutes for these commands. Stage-specific phrases such as `确认并应用 intake package` and `确认并冻结契约` are required for approval steps.

There is also a review obligation between `/goalspec end` and `freeze`: AI must actively present a concise Goal / Criteria / Constraints summary and wait for `确认并冻结契约` before freezing.

## Start gate

`/goalspec start` refuses to open intake unless the business worktree is clean relative to `HEAD`. A dirty worktree is snapshotted into `.goalspec/artifacts/intake/` by `source` at intake time, and that snapshot is frozen *before* `freeze` runs — so freeze cannot catch a stale or contaminated snapshot. Commit or stash business changes before starting.

- Clean means no modified or untracked business files vs `HEAD`.
- `.goalspec/*`, `AGENTS.md`, and `CLAUDE.md` are framework files and do not count as business changes.
- A non-git project is treated as clean.

This guards intake provenance, not implementation: once intake opens, normal editing resumes.

## Run gate

`/goalspec run` refuses execution unless all preconditions pass:

- Goal, Criteria, and Constraints are frozen.
- No blocking questions remain.
- The Goal-Driven Prompt exists.
- Frozen artifact hashes and prompt hash are current.
- The effective scope hash matches `state.yaml.scope_hash` (no unapproved path expansion; see [Scope amendments](#scope-amendments)).
- The state is not `reopen_required`.

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
NEXT_USER_ACTION: Review the close package, then run /goalspec close to archive and execute the configured delivery mode.
```

Blocked run output includes `GOALSPEC_RUN_ALLOWED: false`, a `BLOCKER`, and `NEXT_USER_ACTION`.

## Run loop and stop conditions

`/goalspec run` is not a single shot. When it returns `GOALSPEC_RUN_ALLOWED: true`, the Goal-Driven Prompt drives the agent session to loop:

```text
Master Evaluation -> Subagent Work -> Evidence/Progress Report
```

until one of four stop conditions fires. The loop lives inside a single `/goalspec run`; Goalspec has no separate `loop` command.

Stop conditions, all enforced in CLI gates the loop cannot bypass (`run` / `judge apply`):

1. **All required Criteria pass** — the next `/goalspec run` generates the close package and hands off to `/goalspec close`.
2. **Iteration cap (token stop-loss)** — each `judge apply` (one Master verdict = one round) increments `state.run_loop.iteration`. At `profile.run_loop.max_iterations` (default 8) the loop is marked `capped`: further `run` and `judge apply` refuse until a human `/goalspec close` or `/goalspec reopen` resets it. The cap is read from profile, so it is fixed before the loop runs.
3. **No-progress (stalled)** — `judge apply` also records a verdict fingerprint (every criterion's latest verdict, in contract order) and the current evidence hash. If both are unchanged for `profile.run_loop.stall_threshold` (default 3) consecutive rounds, the loop is marked `stalled`. `capped` means the budget is exhausted (close, or raise the cap); `stalled` means the loop is spinning on an unsolvable spec defect (reopen). The double condition — verdict and evidence both unchanged — is what keeps normal multi-round iteration from being killed: as long as any verdict is still moving, the loop is making progress. Exempted when all required Criteria already pass.
4. **Judgment-kind Criteria** — once every `machine` criterion has a pass verdict, the loop will not blindly retry the remaining `judgment`-kind criteria; those need human/Master resolution, not Subagent iteration.

`status` surfaces `capped`/`stalled` through `NEEDS_HUMAN_CONFIRMATION` and a targeted `NEXT_USER_ACTION`.

### Driving the loop unattended

Goalspec ships no scheduler. To advance the loop without a human typing each `/goalspec run`, drive it from outside — the stop conditions keep it bounded:

- Claude Code `/loop`, or cron/CI calling `.goalspec/goalspec run` on a cadence.

Only the `frozen -> ready_to_close` execution span is looped. The human gates (`start` / `end` / `close`) are never crossed automatically.

```yaml
# .goalspec/project/profile.yaml
run_loop:
  max_iterations: 8     # judge-apply rounds before capped
  stall_threshold: 3    # consecutive unchanged rounds before stalled
```

## Loop engineering observability

The run-loop is observable and self-instrumenting. Four mechanisms layer on top of the Master/Subagent loop — none of them change the success condition (Criteria pass), they record what the loop tried, close the self-claim gap, and let a confirmed failure leave an improvement suggestion instead of spinning silently.

### Sensor verification (closes the self-claim gap)

`profile.commands.{test,build,lint,typecheck}` only run at `/goalspec close`. Without an intermediate check, a `pass` verdict could rest on the Subagent's self-reported `exit_code`. The sensor closes that gap at `judge apply` time:

- For every `evidence_ref` cited in a **pass** verdict, if that evidence has `reproducible: true`, the sensor re-runs the evidence's `command` in the project root.
- Non-zero exit → the verdict is **rejected** (not auto-downgraded). The Master stays the sole verdict author.
- Only `reproducible: true` evidence is ever re-run — side-effect safety. Negative verdicts never trigger the sensor. The schema rejects `reproducible: true` without a non-empty `command`.

```yaml
# evidence.yaml — reproducible evidence is re-verified by the sensor at judge time
- id: ev_01
  criteria_refs: ["c1"]
  command: "pytest -q tests/test_c1.py"
  exit_code: 0
  reproducible: true        # set false for evidence with side effects (network, writes)
```

### trace.yaml (per-round audit trail)

Each `judge apply` (one Master verdict = one round) appends one entry to `.goalspec/active/trace.yaml`:

```yaml
- iteration: 3
  judged_at: "2026-06-21T10:05:00Z"
  criterion_ref: c2
  verdict: fail
  master_reasoning: "..."
  evidence_diff: ["ev_04"]          # evidence ids present when the evidence hash moved
  stop_check:
    outcome: continue               # continue | capped | stalled
    why: "iteration 3 < max_iterations=8"
  contract_hash: sha256:...
  prompt_hash: sha256:...
```

`trace.yaml` is append-only history. It is archived with the rest of `active/` at close.

### trajectory (derived loop state)

Each round, Goalspec recomputes `state.run_loop.trajectory` — a pure derivation from `verdict.yaml` + contract, no Master input:

```yaml
run_loop:
  trajectory:
    tried_paths: ["c1=pass", "c2=fail"]
    failed_approaches: ["c2=fail"]
    current_blocker: "c2: fail - <reason>"
    next_step: "c2"
```

### harness-improvement-candidate.yaml (advisory, human-gated promotion)

When the loop hits a confirmed failure (`capped` or `stalled`), Goalspec emits `.goalspec/active/harness-improvement-candidate.yaml` (idempotent: one per active goal). The framework fills only the failure provenance — `failure_kind`, `task_signature`, `failure_step`, and `rule_version` (including the `master.md` hash the failure ran under):

```yaml
status: proposed               # proposed | under_review | promoted | rejected
failure_kind: stalled          # capped | stalled
task_signature:
  repeatedly_failing_criteria: ["c2"]
failure_step:
  iteration: 6
  refused_criterion: c2
  validator_reason: "no progress for 3 consecutive rounds ..."
rule_version:
  contract_hash: sha256:...
  prompt_hash: sha256:...
  master_md_hash: sha256:...   # rule-version provenance
proposed_target: {}            # LEFT FOR MASTER/HUMAN — which rule file to change
prediction: ""                 # LEFT FOR MASTER/HUMAN — falsifiable statement
reviewed_by_human: false
promoted: false                # only a human may set this true, after regression passes
```

Promotion is **human-gated**: the framework never fills `proposed_target` / `prediction` and never sets `promoted: true`. It is advisory — the loop leaves evidence about its own failure; a human decides whether to act on it.

### LOOP_CONTRACT (read-only status view)

When the contract is frozen, `status` appends an 11-item loop-contract view — assembled from `goal.md` / `contract.yaml` / `profile.yaml` / `state.yaml`, written nowhere:

```text
LOOP_CONTRACT:
  name: <active_goal_id>
  trigger: /goalspec run (state=running)
  goal: <first line of goal.md Intent>
  input: contract.yaml (frozen), evidence.yaml, verdict.yaml, trace.yaml
  scope: <allowed_paths>
  tools: <profile test/build/lint/typecheck>
  verification: profile commands at /goalspec close; sensor re-run of reproducible evidence at judge apply
  stop: max_iterations=8, stall_threshold=3, judgment-kind gate, all-required-pass
  escalation: /goalspec reopen <reason> (capped -> close-or-reopen; stalled -> reopen), /goalspec close (human gate)
  state: iteration=3, last_outcome=continue, trajectory={...}
  cleanup: close archives active/ to history/vNNNN/, applies memory-patch, resets run_loop
```

It exists to make the loop's contract inspectable in one place — what triggers it, what feeds it, when it stops, where it escalates.

## Reopen policy

Use `/goalspec reopen <reason>` only when the frozen Goal, Criteria, or Constraints is no longer a valid acceptance basis: it is wrong, incomplete, contradictory, impossible under the current Constraints, or no longer matches the human's intended acceptance result.

Do not reopen because implementation is unfinished. If the contract is still correct, stay in `running` and continue the Master/Subagent loop.

### Reopen flow

1. The human runs `/goalspec reopen <reason>`.
2. The current frozen execution basis becomes invalid: do not keep implementing, judging, running the old prompt, or closing the old close package.
3. Goalspec creates `.goalspec/active/reopen-impact.yaml`.
4. Fill `reopen-impact.yaml`: explain why the frozen basis failed, classify each Criterion, list reusable work, list evidence to refresh, and mark whether each affected item needs `rejudge_only` or `reimplement_needed`.
5. The human reviews the impact and approves the revised Goal/Criteria/Constraints.
6. Freeze the revised contract again; only then may `/goalspec run` resume.

### Criteria impact

Reopen is a contract repair step, not a full restart by default. Completion is tracked at the Criteria/evidence/verdict level:

- `unchanged`: keep the Criterion ID; reuse valid code; replay or re-judge evidence as needed.
- `modified`: keep or update implementation as needed; collect fresh evidence; judge again.
- `added`: implement, collect evidence, and judge.
- `removed`: remove from the required completion set.

Only a Goal or Constraint change with global effect should force full re-validation.

### Reopen vs next change

If the new request changes what counts as complete for the current Goal, reopen the current change.

If it is an extra improvement that does not affect current completion, close the current change first and start a new `/goalspec start <intent>`.

## Scope amendments

Scope is the Constraints projection: `allowed_paths` and `forbidden_paths` in `contract.yaml`. Every changed business file must match an allowed pattern and match no forbidden pattern, or `/goalspec run` close-readiness and `scope-check` refuse. Scope is hashed into `state.yaml.scope_hash`, so an unapproved path expansion makes `run` and `close-readiness` stale just like any other frozen artifact.

When implementation legitimately needs to touch paths that still serve the current Goal **without changing Goal, Criteria, or semantic Constraints**, record a human-approved expansion instead of reopening:

```text
.goalspec/goalspec scope amend --allow <glob> [--allow <glob> ...] --reason <why>
```

This is the Constraints-projection lane; `/goalspec reopen` is the contract lane. The split is deliberate: `scope amend` appends an `approved` amendment to `.goalspec/active/scope-amendments.yaml` and never overwrites `contract.yaml`, while `reopen` demotes the frozen contract back to `draft` and forces re-review / re-approve / re-freeze. `scope amend` therefore:

- requires `--reason` and at least one `--allow` glob;
- refuses any glob that would authorize a path also matched by `forbidden_paths`;
- records old/new `scope_hash` (in both the amendment and `state.yaml`);
- regenerates `.goalspec/active/goal-driven-prompt.md` if it exists (the prompt embeds the effective scope, so `prompt_hash` moves too);
- if the change already reached `ready_to_close` or `closing`, rolls back to `running` and clears `close_package_hash`, so the next `/goalspec run` regenerates the close package.

Use `reopen` only when Goal, Criteria, or semantic Constraints themselves changed; use `scope amend` when the Goal and contract are still correct and only the allowed-path table is too narrow.

Inspect the effective table at any time:

```text
.goalspec/goalspec scope effective
```

It prints `allowed_paths` (contract patterns plus approved amendments), `forbidden_paths`, and the current `scope_hash`.

## Close

`/goalspec close` is the only user-visible closure command. It confirms the current close package and authorizes the configured delivery mode:

1. Validate the close package and recompute every bound hash (contract, evidence, verdict, memory-patch, changed-files, suggested delivery, close package).
2. Run final verification (test/build/lint/typecheck, plus optional `audit`/`sast` security & dependency gates, from `.goalspec/project/profile.yaml`). These must be sandbox-reproducible — a command needing a live DB/Redis/Browser/LLM fails close as if the code were broken; move such tests to `environment.smoke_tests` / `fidelity` / CI. On failure, close names the failing command and exit code, and (if the profile declares external services) flags a likely environment dependency.
3. Run the smoke gate and Ralph Wiggum audit. Each `environment.smoke_tests` entry — a real end-to-end check that physically traverses invariants outside the implementer's control (a real DB engine's constraints, a real service process, real I/O) — runs under its `fidelity` boundary (bootstrap → command → teardown). With no `smoke_tests` configured, close emits `SMOKE_WARNING` + `RALPH_WIGGUM_WARNING` (the all-soft close: pass verdicts not backed by any objective gate) but still succeeds — backward compatible. Set `environment.fidelity.enforce_on_close: true` to make a failing smoke test fail close.
4. Re-check the changed-files hash after final verification, so verification cannot silently add files after package review.
5. Scan for secrets, large files, and disallowed temp files. Password detection stays wide (quote and bare literals, to catch real `.env`-style leaks) but skips function-call assignments (`password=env.get(...)`); `.delivery.scan_allow_paths` exempts known dummy-credential paths (tests/fixtures/docs).
6. Apply the memory patch to `.goalspec/project/**`.
7. Archive active files to `.goalspec/history/vNNNN/` and update `project/versions.yaml`.
8. Execute the configured delivery mode:
   - `github_pr`: create/reuse a delivery branch, commit, push, open a PR, then record delivery metadata.
   - `push_only`: create/reuse a delivery branch, commit, push, and record delivery metadata without creating a PR.
   - `local_commit`: create local commits and delivery metadata without requiring a remote or `gh`.
   - `archive_only`: archive and close without git commits, push, or PR.
9. Enter `closed`.

Close is recoverable. If it fails mid-way it stops at a checkpoint; re-running `/goalspec close` continues from there without repeating the main commit. A stale close package (any bound hash changed since generation) is rejected — re-run `/goalspec run` to regenerate it. Full scope/Constraints-projection readiness is handled by `/goalspec run` and `status`; close validates the reviewed package and rejects unreviewed deltas.

AI tools must not replace `/goalspec close` with manual `git add`, `git commit`, `git push`, `gh pr create`, archive, or `status: closed` edits. If non-GitHub delivery is needed, set `.goalspec/project/profile.yaml` `delivery.mode` explicitly. On failure, report the CLI's blocker and next user action.

Close does not auto-merge the PR, create releases, tag versions, or deploy. Those are out of scope.

### Delivery modes

Delivery is explicit in `.goalspec/project/profile.yaml`:

```yaml
delivery:
  mode: github_pr   # github_pr | push_only | local_commit | archive_only
  remote: origin
  base_branch: main
```

`github_pr` is the default so existing projects do not silently downgrade delivery. Non-GitHub or local-only projects should choose `push_only`, `local_commit`, or `archive_only` before generating the close package.

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

## Constraints

Constraints are the AI's boundaries, kept in two layers:

- `project/constraints.yaml` — long-term project constraints (id, category, `level`, statement, source_refs, applies_to);
- `contract.yaml` constraints — goal-level constraints for the active change.

Every constraint carries a severity `level`:

- `level: hard` — a hard boundary. The Master runs a **Constraint Conformance** check alongside the Coverage Audit: any implementation that violates a `level: hard` constraint must be judged `fail` for that criterion, with a reason including `Constraint violation: <constraint_id>` — even if the Coverage Audit would otherwise pass.
- `level: soft` — a guideline. A violation is noted in the verdict reason but does not by itself fail a criterion.

Constraints are enforced at Master-verdict time, so a constraint violation cannot hide behind a passing Coverage Audit. Authoring guidance lives in the goalspec skill's `references/constraint-extraction.md`.

## Criteria

All entries under `criteria:` are required by default. Do not add repetitive `required: true` fields.

Use `optional_criteria:` for useful ideas that should not block closure.

Each required criterion must be:

- clear;
- decidable from evidence;
- relevant to the Goal;
- minimal, without implementation steps or technology choices.

## Evidence and completion model

Evidence records observable facts and binds them to Criteria. The Subagent may produce evidence.

Evidence with `reproducible: true` carries a `command` that the sensor re-runs at `judge apply` to confirm a pass verdict (see [Sensor verification](#sensor-verification-closes-the-self-claim-gap)). Mark evidence with side effects (network, filesystem writes) `reproducible: false`.

Only the Master Agent may produce final verdicts. A Subagent's self-report, passing tests, or evidence text cannot close the goal.

Completion is tracked through:

- `criteria_ref` -> evidence bindings in `evidence.yaml`;
- latest Master verdict per `criteria_ref` in `verdict.yaml`.

Goalspec does **not** treat internal task lists, work units, or implementation steps as the unit of completion. The `### Workunit:` headings a `goal.md` may use are readability and criteria-traceability groupings only — they are not execution units, do not sequence work, and do not set implementation priority. The Master drives by criterion, not by workunit.

Closure requires all required Criteria to have fresh pass verdicts, Constraints to remain respected, a current `.goalspec/active/close-package.yaml`, final verification to pass, and `.goalspec/goalspec close` to complete the configured delivery mode.

## Status

Run status whenever unsure:

```bash
.goalspec/goalspec status
```

It reports `STATE`, `GOAL`, `FROZEN`, `PROMPT_READY`, `RUN_ALLOWED`, `CLOSE_READY`, `NEEDS_HUMAN_CONFIRMATION`, `BLOCKERS`, `CLOSE_BLOCKERS`, `UNMET_CRITERIA`, `SCOPE_HASH`, and `NEXT_USER_ACTION`. When the contract is frozen it also appends a `LOOP_CONTRACT:` view (see [Loop engineering observability](#loop-engineering-observability)).
