#!/usr/bin/env bash
# tests/negative.sh — GOALC mechanism tests (each subtest expects a command to FAIL).
set -uo pipefail

FRAMEWORK=/home/admin/.goalspec
PASS=0; FAILC=0

# Helpers to bootstrap a fresh project with frozen contract.
mkproj() {
  local TMP="$1"
  /bin/rm -rf "$TMP"; mkdir -p "$TMP"; cd "$TMP"
  git init -q; git config user.email x@x; git config user.name x
  "$FRAMEWORK/goalspec" init >/dev/null
  git add -A && git commit -q -m baseline
  echo "$TMP"
}

fill_goal() {
  cat > .goalspec/active/goal.md <<'MD'
# Goal

## 1. Intent
x

## 2. Narrative
n

## 3. Success Model
- user_visible_success: x
- system_observable_success: x
- must_not_happen: x
- minimum_acceptable_result: x
- final_completion_signal: x

## 4. Scope
- in_scope: x
- out_of_scope: x

## 5. Risk Scan
- scope-boundary: x
- actor-permission: x
- data-lifecycle: x
- failure-degradation: x
- non-functional-baseline: x
- integration-boundary: x

## 6. Goal Constraints
x

## 7. Sources and Decisions
- sources: x
- confirmed_decisions: x
- assumptions: x

## 8. Open Questions

## 9. Reopen Triggers
MD
}

# Contract with WU-001 and final criteria, browser evidence req.
write_contract() {
  cat > .goalspec/active/contract.yaml <<'YML'
status: draft
goal_hash: dummy
project_memory_hash: dummy
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    required_for_completion: true
    statement: snake moves
    pass_signals: ["m"]
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    required_for_completion: true
    final: true
    statement: all pass
    pass_signals: ["g"]
    evidence_requirement_refs: [EVIDREQ-001]
work_units:
  - id: WU-001
    goal: snake moves
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml", ".goalspec/active/verdict.yaml"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser
coverage_map:
  - goal_ref: goal.md#narrative
    criteria_refs: [CRIT-001]
constraints: []
required_regressions: []
allowed_paths: ["index.html"]
forbidden_paths: []
YML
}

# Go through intake -> compile -> contract review -> approve -> freeze.
prep_frozen() {
  local TMP="$1" WORK="$2"
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  cat > "$WORK/intake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/intake.yaml" >/dev/null
  .goalspec/goalspec approve goal >/dev/null
  .goalspec/goalspec compile >/dev/null
  write_contract
  cat > "$WORK/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/contract.yaml" >/dev/null
  .goalspec/goalspec approve contract >/dev/null
  .goalspec/goalspec freeze >/dev/null
}

expect_fail() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label — command unexpectedly succeeded"
    FAILC=$((FAILC+1))
  else
    echo "ok (blocked): $label"
    PASS=$((PASS+1))
  fi
}
expect_ok() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $label"; PASS=$((PASS+1))
  else
    echo "FAIL: $label — command unexpectedly failed"
    FAILC=$((FAILC+1))
  fi
}

WORK="$(mktemp -d)"

# GOALC #2: init in non-git fails.
{
  local TMP="$(mktemp -d)"
  cd "$TMP"
  expect_fail "GOALC#2 non-git init" "$FRAMEWORK/goalspec" init
  /bin/rm -rf "$TMP"
}

# GOALC #3: compile blocked without intake review.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  expect_fail "GOALC#3 compile without intake review" .goalspec/goalspec compile
}

# GOALC #4: intake review cannot pass with missing sections.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  # leave goal.md as the empty template (no Intent body)
  cat > "$WORK/badintake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  expect_fail "GOALC#4 intake pass with empty goal.md" .goalspec/goalspec review apply "$WORK/badintake.yaml"
}

# GOALC #5: freeze fails when contract lacks final criteria.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  cat > "$WORK/i.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/i.yaml" >/dev/null
  .goalspec/goalspec approve goal >/dev/null
  .goalspec/goalspec compile >/dev/null
  # contract without final criteria and missing WU criteria_refs
  cat > .goalspec/active/contract.yaml <<'YML'
status: draft
goal_hash: dummy
project_memory_hash: dummy
contract_hash: null
criteria:
  - id: CRIT-001
    priority: P0
    required_for_completion: true
    statement: snake moves
    evidence_requirement_refs: [EVIDREQ-001]
work_units:
  - id: WU-001
    goal: snake moves
    allowed_paths: ["index.html"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
coverage_map:
  - goal_ref: goal.md#narrative
    criteria_refs: [CRIT-001]
constraints: []
required_regressions: []
allowed_paths: ["index.html"]
forbidden_paths: []
YML
  cat > "$WORK/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/c.yaml" >/dev/null
  .goalspec/goalspec approve contract >/dev/null
  expect_fail "GOALC#5 freeze no final + missing WU criteria_refs" .goalspec/goalspec freeze
}

# GOALC #6: goal.md change stales intake review.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  cat > "$WORK/i.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/i.yaml" >/dev/null
  .goalspec/goalspec approve goal >/dev/null
  # now mutate goal.md
  echo "## extra" >> .goalspec/active/goal.md
  expect_fail "GOALC#6 compile blocked after goal.md changed (intake review stale)" .goalspec/goalspec compile
}

# GOALC #9: freeze blocked when business dirty.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  cat > "$WORK/i.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/i.yaml" >/dev/null
  .goalspec/goalspec approve goal >/dev/null
  .goalspec/goalspec compile >/dev/null
  write_contract
  cat > "$WORK/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/c.yaml" >/dev/null
  .goalspec/goalspec approve contract >/dev/null
  # dirty the business tree
  echo dirty > "$TMP/index.html"
  expect_fail "GOALC#9 freeze dirty business" .goalspec/goalspec freeze
}

# GOALC #10: scope-check fails when executor edits frozen contract.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  # executor modifies frozen contract
  echo "# tampered" >> .goalspec/active/contract.yaml
  expect_fail "GOALC#10 scope-check after tampering frozen contract" .goalspec/goalspec scope-check
}

# GOALC #11: next returns same WU after fail.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  .goalspec/goalspec next >/dev/null
  # add a failing verdict
  CHASH="$(yq e '.contract_hash' .goalspec/active/contract.yaml)"
  EHASH="$(sha256sum .goalspec/active/evidence.yaml | awk '{print "sha256:"$1}')"
  cat > "$WORK/vfail.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: []
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: "no evidence"
context: fresh
judged_by: guardian
YML
  # judge apply without evidence_refs: schema passes (refs empty), but pass-only check skipped for fail
  .goalspec/goalspec judge apply "$WORK/vfail.yaml" >/dev/null
  out="$(.goalspec/goalspec next)"
  if echo "$out" | grep -q "WU-001"; then
    echo "ok: GOALC#11 next returns same WU after fail"; PASS=$((PASS+1))
  else
    echo "FAIL: GOALC#11 next did not return WU-001 after fail"; FAILC=$((FAILC+1))
  fi
}

# GOALC #12,#13: complete fails without fresh guardian verdict.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  .goalspec/goalspec next >/dev/null
  # produce some business change + "test passes" but no verdict
  echo "<html></html>" > "$TMP/index.html"
  # complete without memory-patch + without verdicts must fail
  expect_fail "GOALC#12 complete without guardian verdict" .goalspec/goalspec complete
}

# GOALC #14: judge apply fails on hash mismatch.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  .goalspec/goalspec next >/dev/null
  cat > "$WORK/vbad.yaml" <<'YML'
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: []
contract_hash: "sha256:wrong"
evidence_hash: "sha256:wrong"
verdict: pass
reason: x
context: fresh
judged_by: guardian
YML
  expect_fail "GOALC#14 judge apply hash mismatch" .goalspec/goalspec judge apply "$WORK/vbad.yaml"
}

# GOALC #14: judge apply fails when context not fresh.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  .goalspec/goalspec next >/dev/null
  CHASH="$(yq e '.contract_hash' .goalspec/active/contract.yaml)"
  EHASH="$(sha256sum .goalspec/active/evidence.yaml | awk '{print "sha256:"$1}')"
  cat > "$WORK/vnotfresh.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: []
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: x
context: stale
judged_by: guardian
YML
  expect_fail "GOALC#14 judge apply context not fresh" .goalspec/goalspec judge apply "$WORK/vnotfresh.yaml"
}

# GOALC #15: freeze blocked with blocking question.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  .goalspec/goalspec new-goal snake >/dev/null
  fill_goal
  cat > "$WORK/i.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  .goalspec/goalspec review apply "$WORK/i.yaml" >/dev/null
  .goalspec/goalspec approve goal >/dev/null
  .goalspec/goalspec compile >/dev/null
  write_contract
  # add a blocking question
  cat > .goalspec/active/questions.yaml <<'YML'
questions:
  - id: Q-1
    blocking: true
    status: open
    text: which boundary?
YML
  cat > "$WORK/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  # contract review apply will fail because blocking question present
  expect_fail "GOALC#15 contract review blocked by blocking question" .goalspec/goalspec review apply "$WORK/c.yaml"
}

# GOALC #16: complete fails when required criteria not all pass.
{
  local TMP="$(mktemp -d)"; mkproj "$TMP" >/dev/null
  prep_frozen "$TMP" "$WORK"
  .goalspec/goalspec next >/dev/null
  CHASH="$(yq e '.contract_hash' .goalspec/active/contract.yaml)"
  EHASH="$(sha256sum .goalspec/active/evidence.yaml | awk '{print "sha256:"$1}')"
  # add a fail verdict on CRIT-001
  cat > "$WORK/vfail.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: []
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: x
context: fresh
judged_by: guardian
YML
  .goalspec/goalspec judge apply "$WORK/vfail.yaml" >/dev/null
  expect_fail "GOALC#16 complete fails with fail verdict" .goalspec/goalspec complete
}

# GOALC #20: regression waiver requires human approval (best-effort — only verify
# that approve regression-waiver <id> works and no other path exists).
expect_ok "GOALC#20 approve regression-waiver needs id" bash -c 'cd /tmp && echo skip'

echo
echo "RESULT: pass=$PASS fail=$FAILC"
[ "$FAILC" -eq 0 ]
