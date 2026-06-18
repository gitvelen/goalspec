#!/usr/bin/env bash
# prompt.sh — frozen Goal/Criteria/Constraints artifacts and run prompt.

goalspec_prompt_write_frozen_artifacts() {
  local sf="$GOALSPEC_ROOT/active/state.yaml"
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  local goal_hash contract_hash confirmed_at generated_at
  goal_hash="$(goalspec_goal_hash)"
  contract_hash="$(goalspec_contract_hash)"
  confirmed_at="$(yq e '[.approvals[] | select(.kind == "contract")] | .[-1].approved_at // ""' "$sf")"
  generated_at="$(goalspec_now)"

  {
    printf 'status: frozen\n'
    printf 'source: goal.md\n'
    printf 'goal_hash: "%s"\n' "$goal_hash"
    printf 'contract_hash: "%s"\n' "$contract_hash"
    printf 'confirmed_at: "%s"\n' "$confirmed_at"
    printf 'content: |-\n'
    sed 's/^/  /' "$GOALSPEC_ROOT/active/goal.md"
  } > "$GOALSPEC_ROOT/active/goal.yaml"

  {
    printf 'status: frozen\n'
    printf 'goal_hash: "%s"\n' "$goal_hash"
    printf 'contract_hash: "%s"\n' "$contract_hash"
    printf 'confirmed_at: "%s"\n' "$confirmed_at"
    printf 'criteria:\n'
    yq e '.criteria // []' "$cf" | sed 's/^/  /'
    printf 'optional_criteria:\n'
    yq e '.optional_criteria // []' "$cf" | sed 's/^/  /'
  } > "$GOALSPEC_ROOT/active/criteria.yaml"

  {
    printf 'status: frozen\n'
    printf 'goal_hash: "%s"\n' "$goal_hash"
    printf 'contract_hash: "%s"\n' "$contract_hash"
    printf 'confirmed_at: "%s"\n' "$confirmed_at"
    printf 'constraints:\n'
    yq e '.constraints // []' "$cf" | sed 's/^/  /'
    printf 'allowed_paths:\n'
    yq e '.allowed_paths // []' "$cf" | sed 's/^/  /'
    printf 'forbidden_paths:\n'
    yq e '.forbidden_paths // []' "$cf" | sed 's/^/  /'
  } > "$GOALSPEC_ROOT/active/constraints.yaml"

  yq e -i ".goal_hash = \"$goal_hash\"" "$sf"
  yq e -i ".criteria_hash = \"$(goalspec_criteria_hash)\"" "$sf"
  yq e -i ".constraints_hash = \"$(goalspec_constraints_hash)\"" "$sf"
  yq e -i ".confirmed_at = \"$confirmed_at\"" "$sf"
  yq e -i ".prompt_generated_at = \"$generated_at\"" "$sf"
}

goalspec_prompt_generate() {
  goalspec_prompt_write_frozen_artifacts
  local sf="$GOALSPEC_ROOT/active/state.yaml"
  local pf="$GOALSPEC_ROOT/active/goal-driven-prompt.md"
  local goal_hash criteria_hash constraints_hash generated_at confirmed_at
  goal_hash="$(yq e '.goal_hash' "$sf")"
  criteria_hash="$(yq e '.criteria_hash' "$sf")"
  constraints_hash="$(yq e '.constraints_hash' "$sf")"
  generated_at="$(yq e '.prompt_generated_at' "$sf")"
  confirmed_at="$(yq e '.confirmed_at' "$sf")"

  cat > "$pf" <<EOF
---
goal_hash: "$goal_hash"
criteria_hash: "$criteria_hash"
constraints_hash: "$constraints_hash"
prompt_hash: null
generated_at: "$generated_at"
confirmed_at: "$confirmed_at"
---

# Goal-Driven(1 master agent + 1 subagent) System

You are the Master Agent. Create exactly 1 Subagent when the AI tool supports explicit subagents. If the tool does not support subagents, simulate role separation with visible "Master Evaluation", "Subagent Work", and "Evidence/Progress Report" sections.

## Frozen Goal

$(sed 's/^/> /' "$GOALSPEC_ROOT/active/goal.md")

## Frozen Criteria For Success

\`\`\`yaml
$(yq e '.criteria' "$GOALSPEC_ROOT/active/criteria.yaml")
\`\`\`

## Optional Criteria

\`\`\`yaml
$(yq e '.optional_criteria' "$GOALSPEC_ROOT/active/criteria.yaml")
\`\`\`

## Frozen Constraints

\`\`\`yaml
$(yq e '.constraints' "$GOALSPEC_ROOT/active/constraints.yaml")
\`\`\`

## Control Rules

The frozen Goal above is the final and only goal for the Subagent.
Internal tasks, attempts, execution scopes, work units, test runs, and implementation steps are not success standards.
Criteria satisfaction is the only success condition.
Subagent cannot declare final success.
The Master Agent must strictly evaluate progress against the frozen Criteria.
The Master Agent or Guardian may produce final verdicts; the Subagent may only produce evidence.
Evidence must bind to Criteria and may bind to internal attempts for traceability.
During execution, do not modify Goal, Criteria, or Constraints.
If Goal, Criteria, or Constraints appear wrong, insufficient, or impossible under the Constraints, stop and request \`/goalspec reopen <reason>\`.
Continue Master Evaluation -> Subagent Work -> Evidence/Progress Report until all required Criteria pass, the user stops the process, or a blocking ambiguity requires human input.
EOF

  local phash
  phash="$(goalspec_prompt_hash)"
  sed -i "s/^prompt_hash: null/prompt_hash: \"$phash\"/" "$pf"
  yq e -i ".prompt_hash = \"$phash\"" "$sf"
}
