#!/usr/bin/env bash
# tests/run_all.sh — runs the entire GOALC acceptance suite.
# Each test exits 0 on pass, non-zero on fail. This script aggregates results.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track failures across all suites.
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_TESTS=()

run_suite() {
  local file="$1"
  local name
  name="$(basename "$file" .sh)"
  echo
  echo "=== $name ==="
  if bash "$file"; then
    echo "  [$name] SUITE PASS"
  else
    echo "  [$name] SUITE FAIL"
    FAILED_TESTS+=("$name")
    return 1
  fi
}

# Smaller suites first (positive lifecycle), then negative per GOALC clause.
SUITES=(
  "$TESTS_DIR/smoke.sh"
  "$TESTS_DIR/goalc_01_init.sh"
  "$TESTS_DIR/goalc_02_non_git_init.sh"
  "$TESTS_DIR/goalc_03_compile_freeze_next_blocked.sh"
  "$TESTS_DIR/goalc_04_intake_schema.sh"
  "$TESTS_DIR/goalc_05_contract_freeze_schema.sh"
  "$TESTS_DIR/goalc_06_goal_change_stale.sh"
  "$TESTS_DIR/goalc_07_contract_change_stale.sh"
  "$TESTS_DIR/goalc_08_mpatch_change_stale.sh"
  "$TESTS_DIR/goalc_09_freeze_dirty.sh"
  "$TESTS_DIR/goalc_10_scope_check_frozen.sh"
  "$TESTS_DIR/goalc_11_next_scheduling.sh"
  "$TESTS_DIR/goalc_12_complete_no_verdict.sh"
  "$TESTS_DIR/goalc_13_executor_self_complete.sh"
  "$TESTS_DIR/goalc_14_judge_apply_invalid.sh"
  "$TESTS_DIR/goalc_15_blocking_question.sh"
  "$TESTS_DIR/goalc_16_complete_nonpass.sh"
  "$TESTS_DIR/goalc_17_complete_success.sh"
  "$TESTS_DIR/goalc_18_complete_artifacts.sh"
  "$TESTS_DIR/goalc_19_complete_attribution.sh"
  "$TESTS_DIR/goalc_20_regression_inject.sh"
  "$TESTS_DIR/goalc_21_status_fields.sh"
  "$TESTS_DIR/goalc_22_approval_only.sh"
)

# Filter to a subset when GOALC_ONLY is set (debugging).
if [ -n "${GOALC_ONLY:-}" ]; then
  SUITES=( "$TESTS_DIR/${GOALC_ONLY}.sh" )
fi

overall=0
for s in "${SUITES[@]}"; do
  if [ ! -f "$s" ]; then
    echo "  [missing] $s" >&2
    overall=1
    continue
  fi
  run_suite "$s" || overall=1
done

echo
if [ "$overall" -eq 0 ]; then
  echo "ALL SUITES GREEN"
else
  echo "SUITES FAILED: ${FAILED_TESTS[*]}"
fi
exit "$overall"
