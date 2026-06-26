#!/usr/bin/env bash
# GOALC #67: a Master verdict that flags a level:hard constraint violation is
# a legitimate fail (Constraint Conformance). judge apply accepts it, the
# criterion stays fail, and close is blocked — meeting a criterion by breaking
# a hard constraint is NOT acceptance.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-67-constraint-conformance
"$REPO_GS" start "ship feature under a hard constraint" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
Ship feature under a hard constraint.
MD
cat > "$REPO/.goalspec/active/constraint-suggestions.yaml" <<'YML'
project_profile:
  merge: {}
project_constraints:
  - id: no-new-runtime-deps
    category: dependency
    level: hard
    statement: No new third-party runtime dependency may be added beyond the current lockfile.
    source_refs:
      - conversation
    applies_to:
      - all-goals
goal_constraints: []
open_questions: []
discarded_candidates: []
YML
"$REPO_GS" approve intake-package >/dev/null
"$REPO_GS" intake apply-suggestions >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

# The hard constraint is loaded into the prompt the Master reads, with the
# conformance duty spelled out.
prompt="$REPO/.goalspec/active/goal-driven-prompt.md"
/bin/grep -q 'no-new-runtime-deps' "$prompt" \
  && /bin/grep -q 'Constraint Conformance' "$prompt" \
  && ok "Master prompt carries the hard constraint + conformance duty" \
  || bad "Master prompt missing hard constraint / conformance duty"

# Master judges CRIT-001 fail because the implementation violated the hard
# constraint, even though the behavior itself may look satisfied.
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"
echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
ehash="$(cur_evidence_hash)"

tmp="$TESTS_TMP_ROOT/v67"; mkdir -p "$tmp"
cat > "$tmp/v-CRIT-001.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: fail
reason: |
  Coverage audit:
  - claim: "behavior A observed"
    evidence: [EV-001]
    sufficiency: sufficient
  Constraint violation: no-new-runtime-deps — implementation added a new runtime dependency (lodash) beyond the lockfile to satisfy this criterion. Meeting a criterion by breaking a level:hard constraint is NOT acceptance.
context: fresh
evaluated_by: master
YML

if "$REPO_GS" judge apply "$tmp/v-CRIT-001.yaml" >/dev/null 2>"$TESTS_TMP_ROOT/judge67.err"; then
  ok "judge apply accepts constraint-violation fail verdict"
else
  bad "judge apply rejected constraint-violation fail verdict"
  cat "$TESTS_TMP_ROOT/judge67.err" >&2
fi

verdicts="$REPO/.goalspec/active/verdict.yaml"
/bin/grep -q 'fail' "$verdicts" \
  && /bin/grep -q 'Constraint violation: no-new-runtime-deps' "$verdicts" \
  && ok "verdict records fail with the constraint violation" \
  || bad "verdict did not record the constraint-violation fail"

# Close must be blocked: a hard-constraint violation means the goal is not
# substantively accepted, regardless of any superficial criterion pass.
if "$REPO_GS" close >/dev/null 2>"$TESTS_TMP_ROOT/close67.err"; then
  bad "close succeeded despite a hard-constraint violation fail"
else
  ok "close blocked while a hard-constraint violation stands as fail"
fi

[ "$TESTS_FAIL" -eq 0 ]
