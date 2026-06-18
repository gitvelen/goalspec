#!/usr/bin/env bash
# tests/run_all.sh — runs the entire GOALC acceptance suite.
# Each test exits 0 on pass, non-zero on fail. This script aggregates results.
# Suite list is discovered automatically: smoke.sh runs first (positive
# lifecycle), then every goalc_*.sh in numeric-prefix order. To add a test,
# just drop a goalc_NN_<name>.sh file in tests/ — no registration needed.
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

# Build the suite list. smoke.sh first (comprehensive positive lifecycle), then
# goalc_*.sh sorted by the NN numeric prefix so clauses run in spec order.
build_suites() {
  SUITES=( "$TESTS_DIR/smoke.sh" )
  # shellcheck disable=SC2012,SC2207
  local found
  found="$(ls "$TESTS_DIR"/goalc_*.sh 2>/dev/null | sort -t_ -k2 -n)"
  if [ -n "$found" ]; then
    while IFS= read -r f; do
      SUITES+=( "$f" )
    done <<<"$found"
  fi
}

build_suites

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
