# Constraint Extraction

Use this after `/goalspec end` or when `status` asks for an intake package.

## Inputs

Read:

- `.goalspec/active/intake-conversation.md`
- `.goalspec/active/intake-sources.yaml`
- referenced source snapshots under `.goalspec/artifacts/intake/`
- any explicit user corrections in the current turn

## Output

Write `.goalspec/active/constraint-suggestions.yaml`:

```yaml
project_profile:
  merge: {}
project_constraints: []
goal_constraints: []
open_questions: []
discarded_candidates: []
```

## Classification

Extract any statement that limits implementation, runtime, environment, compatibility, security, privacy, permissions, data lifecycle, failure behavior, performance baseline, deployment, or verification.

- Put facts in `project_profile.merge`: language, framework, package manager, runtime, default commands, services, env vars.
- Put future-wide rules in `project_constraints[]`.
- Put current-change-only rules in `goal_constraints[]`.
- Put implementation steps, file lists, class/function names, and unconfirmed plans in `discarded_candidates[]`.
- Put unclear or high-impact items in `open_questions[]` and ask the human.

## Fields

Use these fields for project constraints:

```yaml
- id: security-no-secret-logging
  category: security
  level: hard
  statement: Do not log secrets or user private data.
  source_refs:
    - "[D5]"          # capture Confirmed Decision id (NOT a vague "conversation")
  applies_to:
    - all-goals
```

Use these fields for goal constraints:

```yaml
- id: goal-cache-output-equivalence
  level: hard
  statement: Cache must not change generated output semantics.
  source_refs:
    - "[D3]"          # capture Confirmed Decision id
    - docs/spec.md    # or a concrete sourced-doc path from intake-sources
```

### Source references (provenance traceability)

Every `source_refs` entry MUST be grep-locatable, so the intake-capture review
can mechanically verify the constraint traces back to user intent:

- A capture **Confirmed Decision id** (e.g. `[D8]`) or **Acceptance Signal id**
  for anything the user said. The capture numbers user decisions D1..Dn; cite
  that id, not the whole conversation.
- A concrete sourced-doc path (e.g. `docs/spec.md`, matching `intake-sources.yaml`)
  for claims adopted from an intake source (also subject to the source-claim
  laundering review).

Do NOT use the vague `conversation`. It cannot be grepped to a specific user
point, so the review cannot confirm the constraint actually traces to what the
user said — a silent downgrade or a dropped acceptance signal then sails through
uncited.

### Downgrades must be explicit

A strong user constraint that you cannot make directly observable may be marked
`level: soft`, but the `statement` MUST say why (e.g. "soft: not directly
observable; enforced via criterion CRIT-X") and which Decision it downgrades. A
silent hard→soft downgrade — or dropping a strong acceptance signal entirely — is
caught by the intake-capture review `downgrade` check. Prefer decomposing the
strong constraint into observable sub-constraints (hard) over downgrading it.

## Verifiability

A `level: hard` constraint is enforced at acceptance: the Master judges the related criterion `fail` if the implementation violates it. So a hard constraint's `statement` MUST be **observable and checkable against evidence** — otherwise the Master cannot judge conformance and it is effectively advisory.

- Write what can be checked (a forbidden dependency, a required behavior, an invariant), not a vague aspiration.
- Prefer a statement that names an observable: a file/package, an API shape, a runtime invariant, a log absence.

**Bad — not checkable, the Master cannot enforce it:**

```yaml
- id: quality-clean
  level: hard
  statement: Code should be clean and well-architected.
```

**Good — observable, the Master can check it from evidence:**

```yaml
- id: no-new-runtime-deps
  level: hard
  statement: No new third-party runtime dependency may be added to src/ beyond the current lockfile.
- id: schema-no-breaking-change
  level: hard
  statement: No existing migration may be altered or dropped; new migrations are append-only.
```

If a constraint cannot be made observable, either mark it `level: soft` (advisory only) or move it to `open_questions[]` and ask the human.

## Reward hacking: lock the check itself (test-immutable boundary)

If the run-loop's only goal is "make the test green," an agent may find the cheapest path to green is **breaking the test, not fixing the code** — delete an assert, mock everything, hardcode the expected value, wrap in try/except. This is reward hacking: the optimizer exploits a hole in the metric instead of solving the task. The defense is a second boundary the agent cannot cross: the test files themselves.

The framework does **not** forbid `test/` by default — many changes legitimately touch tests (TDD writes the test first). Instead, when extracting constraints for a change where a test suite is the verifier, **declare that suite's directory as `forbidden_paths` in `contract.yaml`** so any edit to it is rejected by `scope-check`:

```yaml
# contract.yaml — forbid mutating the tests that verify THIS change
forbidden_paths:
  - tests/auth/**       # the suite that judges CRIT-LOGIN must not be weakened
```

This pairs with `reproducible: true` evidence (see `evidence-writing.md`): the sensor re-runs the suite to confirm green, and `forbidden_paths` guarantees the suite the sensor runs is the one that was frozen — not a version the agent quietly weakened.

If a change genuinely must update tests (new coverage, correcting a wrong test), make the test change itself a separate, observable, reviewed criterion — never a silent side effect of making another criterion pass.

## Risk Scan coverage

Constraints and the goal.md `Risk Scan` share the same six dimensions. Ensure each is at least evaluated when extracting constraints; do not silently skip one:

- `scope-boundary`, `actor-permission`, `data-lifecycle`, `failure-degradation`, `non-functional-baseline`, `integration-boundary`

Every Risk Scan conclusion in goal.md must resolve to a constraint, a criterion, or an explicit skip with a reason in `open_questions[]` — no floating conclusions.

## Ask Before Proceeding

Stop and ask when:

- a candidate affects security, privacy, permissions, data retention, deployment, or runtime compatibility;
- it is unclear whether a candidate is goal-only or future-wide;
- a document contains plan steps that might be only suggestions;
- applying the constraint would significantly narrow technology choices.
