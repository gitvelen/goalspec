#!/usr/bin/env bash
# tests/lib.sh — shared helpers for the goalspec test suite.
# Sourced by tests/run_all.sh and individual negative_* tests.
set -uo pipefail

FRAMEWORK="${FRAMEWORK:-/home/admin/.goalspec}"

# Counter.
TESTS_PASS=0
TESTS_FAIL=0
TESTS_SEEN=0

# Per-suite scratch root. Each test gets a fresh temp git repo.
# Use suite-name + pid + random to avoid collisions across parallel/sequential runs.
TESTS_TMP_ROOT="${TESTS_TMP_ROOT:-/tmp/goalspec-tests-$(basename "$0" .sh)-$$-$RANDOM}"
mkdir -p "$TESTS_TMP_ROOT"
trap '/bin/rm -rf "$TESTS_TMP_ROOT"' EXIT

# Reporting.
ok()   { TESTS_PASS=$((TESTS_PASS+1)); TESTS_SEEN=$((TESTS_SEEN+1)); echo "  ok: $*"; }
bad()  { TESTS_FAIL=$((TESTS_FAIL+1)); TESTS_SEEN=$((TESTS_SEEN+1)); echo "  FAIL: $*" >&2; }
fail() { bad "$*"; false; }

# fresh_repo <name> -> sets REPO to a brand-new git repo with goalspec init.
fresh_repo() {
  local name="$1"
  REPO="$TESTS_TMP_ROOT/$name"
  /bin/rm -rf "$REPO"
  mkdir -p "$REPO"
  cd "$REPO" || { bad "fresh_repo: cd failed to $REPO"; return 1; }
  git init -q
  git config user.email t@t
  git config user.name t
  REPO_GS="$REPO/.goalspec/goalspec"
}

# fresh_initialized_repo <name> — repo + init + initial baseline commit.
fresh_initialized_repo() {
  fresh_repo "$1"
  # Run init with explicit cwd so we don't depend on global PWD state.
  ( cd "$REPO" && bash "$FRAMEWORK/goalspec" init >/dev/null ) || { bad "init failed"; return 1; }
  ( cd "$REPO" && git add -A && git commit -q -m baseline ) || true
}

# make_minimal_goal_md <path> — writes a goal.md that satisfies the intake schema.
make_minimal_goal_md() {
  local path="$1"
  cat > "$path" <<'MD'
# Goal

## 1. Intent
Sample intent for testing.

## 2. Narrative
Player loads page, action happens, expected outcome.

## 3. Success Model
- user_visible_success: visible effect
- system_observable_success: state change
- must_not_happen: bad thing
- minimum_acceptable_result: core path
- final_completion_signal: all paths green

## 4. Scope
- in_scope: core feature
- out_of_scope: extras

## 5. Risk Scan
- scope-boundary: clear
- actor-permission: none
- data-lifecycle: in-memory
- failure-degradation: graceful
- non-functional-baseline: acceptable
- integration-boundary: none

## 6. Goal Constraints
none

## 7. Sources and Decisions
- sources: human input
- confirmed_decisions: none
- assumptions: standard env

## 8. Open Questions

## 9. Reopen Triggers
MD
}

# write_minimal_contract <path> — writes a draft contract that passes freeze.
make_minimal_contract() {
  local path="$1"
  cat > "$path" <<'YML'
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    required_for_completion: true
    statement: behavior A observed
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    required_for_completion: true
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
work_units:
  - id: WU-001
    goal: do behavior A
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["src/**"]
    forbidden_paths: [".goalspec/project/**", "billing/**"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
coverage_map:
  - goal_ref: goal.md#intent
    criteria_refs: [CRIT-001]
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
}

# Apply a passing intake review + goal approval.
approve_intake_and_goal() {
  local tmp="$TESTS_TMP_ROOT/payloads"
  mkdir -p "$tmp"
  cat > "$tmp/intake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$tmp/intake.yaml" >/dev/null
  "$REPO_GS" approve goal >/dev/null
}

# Compile, write minimal contract, apply passing contract review, approve contract.
# Used as a shortcut to reach the freeze step.
compile_to_contract_reviewed() {
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  local tmp="$TESTS_TMP_ROOT/payloads"
  mkdir -p "$tmp"
  cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
}

# Run the freeze step. Assumes compile_to_contract_reviewed has run.
do_freeze() {
  "$REPO_GS" freeze >/dev/null
}

# Compute current hashes from the project (goal_hash, contract_hash, evidence_hash).
cur_goal_hash()      { sha256sum "$REPO/.goalspec/active/goal.md"      | awk '{print "sha256:"$1}'; }
cur_contract_hash()  {
  local cf="$REPO/.goalspec/active/contract.yaml"
  yq e 'del(.contract_hash) | del(.status)' "$cf" | sha256sum | awk '{print "sha256:"$1}'
}
cur_evidence_hash()  { sha256sum "$REPO/.goalspec/active/evidence.yaml" | awk '{print "sha256:"$1}'; }
cur_mpatch_hash()    { sha256sum "$REPO/.goalspec/active/memory-patch.yaml" | awk '{print "sha256:"$1}'; }
