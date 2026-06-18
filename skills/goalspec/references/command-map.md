# Command Map

Always start with:

```bash
.goalspec/goalspec status
```

Map user-facing commands:

- `/goalspec status` -> `.goalspec/goalspec status`
- `/goalspec start <intent>` -> `.goalspec/goalspec start "<intent>"`
- `/goalspec source <path>` -> `.goalspec/goalspec source <path>`
- `/goalspec end` -> `.goalspec/goalspec end`
- user confirms intake package -> `.goalspec/goalspec approve intake-package && .goalspec/goalspec intake apply-suggestions`
- user confirms Goal/Criteria/Constraints -> freeze reviewed artifacts, generate the Goal-Driven Prompt, then stop
- `/goalspec run` -> `.goalspec/goalspec run`, then read the full prompt before any business-code edit

Internal commands such as `review prompt`, `review apply`, `approve goal`, `compile`, `approve contract`, `freeze`, `judge`, and `complete` are not normal user commands. Use them only when `status` or role instructions require them.

When the user says "继续", do not guess. Run `status` and follow the current state, but do not start implementation unless the user explicitly includes `/goalspec run`.
