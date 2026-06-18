# Command Map

Always start with:

```bash
.goalspec/goalspec status
```

Map user-facing commands:

- `/goalspec status` -> `.goalspec/goalspec status`
- `/goalspec begin <intent>` -> `.goalspec/goalspec intake begin "<intent>"`
- `/goalspec source <path>` -> `.goalspec/goalspec intake add-source <path>`
- `/goalspec end` -> `.goalspec/goalspec intake end`
- user confirms intake package -> `.goalspec/goalspec approve intake-package && .goalspec/goalspec intake apply-suggestions`
- `/goalspec next` -> run `status`, then perform the exact `NEXT_ACTION`

Internal commands such as `review prompt`, `review apply`, `approve goal`, `compile`, `approve contract`, `freeze`, `judge`, and `complete` are not normal user commands. Use them only when `status` or role instructions require them.

When the user says "继续", do not guess. Run `status` and follow the current state.
