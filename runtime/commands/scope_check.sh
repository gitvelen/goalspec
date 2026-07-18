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
  echo "hint: 若这些文件仍服务当前 Goal 且不改 Criteria/Constraints，运行 'goalspec scope amend --allow <glob> --reason <why>' 扩展 scope（无需 reopen）；只有需要改 Criteria/Constraints 本身时才 'goalspec reopen <reason>'" >&2
  if [ "$suggest" = "true" ]; then
    goalspec_scope_print_suggestions
  fi
  exit 1
fi
