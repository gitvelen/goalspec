#!/usr/bin/env bash
# complete.sh — legacy internal completion-readiness gate.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

fail() { echo "complete blocked: $*" >&2; exit 1; }

if ! gate_err="$(goalspec_close_completion_gate 2>&1)"; then
  fail "$gate_err"
fi

goalspec_close_write_package
goalspec_state_set_status ready_to_close

echo "complete: close package ready"
echo "  close_package: $GOALSPEC_ROOT/active/close-package.yaml"
echo "  close_package_hash: $(goalspec_close_package_hash)"
echo "next: review the close package, then run 'goalspec close'"
