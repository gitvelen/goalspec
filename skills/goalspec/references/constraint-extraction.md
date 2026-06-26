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
    - conversation
  applies_to:
    - all-goals
```

Use these fields for goal constraints:

```yaml
- id: goal-cache-output-equivalence
  level: hard
  statement: Cache must not change generated output semantics.
  source_refs:
    - docs/spec.md
```

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
