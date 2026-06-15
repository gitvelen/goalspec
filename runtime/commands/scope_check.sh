#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"
if goalspec_scope_check_run; then
  echo "scope-check: pass"
  exit 0
else
  exit 1
fi
