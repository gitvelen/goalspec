# Command Map

`start`, `end`, `run`, and `close` are human gates — execute the underlying `.goalspec/goalspec <cmd>` ONLY when the user issues the corresponding `/goalspec` slash-command, never self-initiated by the agent (e.g. do not run `intake end` because the intent looks captured; draft the package and wait for `/goalspec end`).

Always start with:

```bash
.goalspec/goalspec status
```

Goalspec is explicit opt-in: only run `.goalspec/goalspec ...` when the user explicitly uses the matching `/goalspec ...` command or clearly asks to enter the formal Goalspec workflow. Normal questions, debugging, or small edits outside that opt-in should stay outside the lifecycle.

Map user-facing commands:

- `/goalspec status` -> `.goalspec/goalspec status`
- `/goalspec start <intent>` -> run status first; only use `.goalspec/goalspec start "<intent>"` when `STATE` is `no_goal` or `closed`
- `/goalspec source <path>` -> `.goalspec/goalspec source <path>`
- `/goalspec end` -> `.goalspec/goalspec end`, then draft Goal, Criteria, Constraints, out-of-scope, and blocking questions, show them to the human, and wait for explicit confirmation before freezing
- `确认并应用 intake package` -> `.goalspec/goalspec approve intake-package && .goalspec/goalspec intake apply-suggestions`
- `确认并冻结契约` -> freeze reviewed artifacts, generate the Goal-Driven Prompt, then stop
- `/goalspec run` -> `.goalspec/goalspec run`, then read the full prompt before any business-code edit
- `/goalspec close` -> `.goalspec/goalspec close`; never replace it with manual git, push, PR, archive, or state edits

Internal commands such as `review prompt`, `review apply`, `approve goal`, `compile`, `approve contract`, `freeze`, `judge`, `complete`, `scope-check`, and `validate` are not normal user commands. Use them only when `status` or role instructions require them.

Two scaffolding helpers are NOT user gates — the run-loop uses them directly to avoid hand-computing hashes:

- `goalspec evidence template <criteria_id>` — emits an evidence skeleton with `contract_hash` / `criteria_refs` / `evidence_requirement_refs` pre-filled from the frozen contract. Use it whenever recording evidence instead of assembling fields by hand.
- `goalspec judge draft <criteria_id> --evidence EV-A,EV-B` — emits a verdict object with `contract_hash` / `evidence_hash` / `evidence_basis_hash` filled and a `coverage_audit` skeleton. Fill the claims, then `goalspec judge apply <file>`. Do not hand-compute hashes or hand-write a `/tmp` apply helper.

When the user says "继续", do not guess. Run `status` and follow the current state, but do not start implementation unless the user explicitly includes `/goalspec run`, and do not close unless the user explicitly includes `/goalspec close`. Bare "确认"/"ok"/silence is not enough for approval; require stage-specific phrases such as `确认并应用 intake package` or `确认并冻结契约`.
