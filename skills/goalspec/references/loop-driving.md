# Run-Loop & External Cadence

## run is already a prompt-driven loop

`/goalspec run` is not a single shot once it lets the agent through
(`GOALSPEC_RUN_ALLOWED: true`). The CLI validates the frozen Goal, Criteria,
Constraints, hashes, and run-loop gates, then prints the Goal-Driven Prompt.
That prompt instructs the current AI tool/session to run the in-session loop:

```text
Master Evaluation
-> Primary Subagent Work
-> Evidence / Progress Report
-> Master Verdict
-> Continue Or Stop
```

The contract model stays only Goal / Criteria / Constraints. Agent roles are
execution roles: the Master directly controls exactly one Primary Subagent; the
Primary Subagent may delegate bounded, Criteria-linked work to Worker Subagents
when useful and supported by the AI tool/session. Workers produce artifacts,
command results, and evidence candidates; only the Master can judge Criteria.

So the Master/Subagent loop lives **inside** one `/goalspec run` as prompt-driven
AI-session behavior. Goalspec does not add a separate runtime `loop` command that
spawns agents or owns their process lifecycle.

## Built-in stop conditions

The run-loop stops on four conditions, all enforced in the CLI gates the loop
cannot bypass (`judge apply` / `run`):

1. **All required Criteria pass** — the next `/goalspec run` generates the close
   package and hands off to the human `/goalspec close` gate.
2. **Iteration cap (token stop-loss)** — each `judge apply` (one Master verdict
   = one round) increments `state.run_loop.iteration`. At
   `profile.run_loop.max_iterations` (read from profile) the loop is marked `capped`:
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

## Heartbeat and external cadence

Goalspec CLI runtime does not ship a scheduler, spawn subagents, monitor
heartbeats, or restart agent processes. Those behaviors belong to the current AI
tool/session when it supports timed wakeups, long-running monitoring, or
background task checks.

The generated prompt therefore uses a conditional heartbeat policy: when the AI
tool/session supports it, the Master should check the Primary Subagent about
every 5 minutes. If the Primary Subagent is inactive, failed, rate-limited,
timed out, idle, returned control, or merely claims completion, the Master must
first evaluate current evidence against the frozen Criteria. If required
Criteria are still unmet and no blocking ambiguity exists, the Master resumes,
replaces, or reissues exactly one Primary Subagent work packet for the unmet
Criteria.

If you want the run-loop to advance without a human typing each `/goalspec run`,
drive it from outside — the stop conditions above keep it bounded:

- **Claude Code `/loop`** — re-issue the run on a cadence; the agent reads
  `goalspec status`, advances the unmet Criteria, lets the Master judge them,
  and stops when status reports `ready_to_close` or capped.
- **cron / CI** — call `.goalspec/goalspec run` on a schedule; the state machine
  and stop conditions keep it from running away.

In every case the human gates (`start` / `end` / `close`) are never crossed
automatically — only the `frozen -> ready_to_close` execution span is looped.
