# Run-Loop & External Cadence

## run is already a loop

`/goalspec run` is not a single shot. Once it lets the agent through
(`GOALSPEC_RUN_ALLOWED: true`), the Goal-Driven Prompt instructs the agent
session to loop:

> Continue Master Evaluation -> Subagent Work -> Evidence/Progress Report
> until all required Criteria pass, the user stops, or a blocking ambiguity
> requires human input.

So the Master/Subagent loop lives **inside** one `/goalspec run`. Goalspec does
not add (and does not need) a separate `loop` command — that would just
re-schedule the loop that `run` already drives.

## Built-in stop conditions

The run-loop stops on four conditions, all enforced in the CLI gates the loop
cannot bypass (`judge apply` / `run`):

1. **All required Criteria pass** — the next `/goalspec run` generates the close
   package and hands off to the human `/goalspec close` gate.
2. **Iteration cap (token stop-loss)** — each `judge apply` (one Master verdict
   = one round) increments `state.run_loop.iteration`. At
   `profile.run_loop.max_iterations` (default 8) the loop is marked `capped`:
   further `run` and `judge apply` refuse until a human `/goalspec close` or
   `/goalspec reopen` resets the counter. The cap is read from profile, so it is
   decided **before** the loop runs, not during.
3. **No-progress (stalled)** — each `judge apply` also records a verdict
   fingerprint (every criterion's latest verdict, in contract order) and the
   current evidence hash. If both are unchanged for
   `profile.run_loop.stall_threshold` (default 3) consecutive rounds, the loop
   is marked `stalled`. `capped` means the budget is exhausted (close, or raise
   the cap); `stalled` means the loop is spinning on an unsolvable spec defect
   (reopen) — the two call for different human actions, so they are distinct
   signals, not one. The double condition (verdict fingerprint **and** evidence
   hash both unchanged) is what keeps normal multi-round iteration from being
   killed: as long as any verdict is still moving, the loop is making progress.
   Exempted when all required Criteria already pass (then the loop is done, not
   stuck).
4. **Judgment-kind Criteria** — once every `machine` criterion has a pass
   verdict, the loop will not blindly retry the remaining `judgment`-kind
   criteria; those need human/Master resolution, not Subagent iteration.

## Driving it unattended

Goalspec does not ship a scheduler. If you want the run-loop to advance without
a human typing each `/goalspec run`, drive it from outside — the stop
conditions above keep it bounded:

- **Claude Code `/loop`** — re-issue the run on a cadence; the agent reads
  `goalspec status`, advances the unmet Criteria, lets the Master judge them,
  and stops when status reports `ready_to_close` or capped.
- **cron / CI** — call `.goalspec/goalspec run` on a schedule; the state machine
  and stop conditions keep it from running away.

In every case the human gates (`start` / `end` / `close`) are never crossed
automatically — only the `frozen -> ready_to_close` execution span is looped.
