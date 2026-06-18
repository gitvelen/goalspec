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

## Ask Before Proceeding

Stop and ask when:

- a candidate affects security, privacy, permissions, data retention, deployment, or runtime compatibility;
- it is unclear whether a candidate is goal-only or future-wide;
- a document contains plan steps that might be only suggestions;
- applying the constraint would significantly narrow technology choices.
