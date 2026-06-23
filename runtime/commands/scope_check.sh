#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

suggest=false
case "${1:-}" in
  --suggest) suggest=true ;;
  "") ;;
  *) echo "usage: goalspec scope-check [--suggest]" >&2; exit 2 ;;
esac

if goalspec_scope_check_run; then
  echo "scope-check: pass"
  exit 0
else
  if [ "$suggest" = "true" ]; then
    goalspec_scope_print_suggestions
  fi
  exit 1
fi
