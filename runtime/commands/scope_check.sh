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
  if [ "$suggest" = "true" ] && [ -n "$GOALSPEC_SCOPE_LAST_UNATTRIBUTED" ]; then
    echo "suggested allowed_paths:" >&2
    goalspec_scope_suggest_patterns "$(printf '%s\n' "$GOALSPEC_SCOPE_LAST_UNATTRIBUTED" | tr ' ' '\n')" | sed 's/^/  - /' >&2
    echo "next: if these files still serve the current Goal without changing Criteria, run: goalspec scope amend --allow <glob> --reason <why>" >&2
  fi
  exit 1
fi
