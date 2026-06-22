#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

usage() {
  cat <<'EOF' >&2
usage:
  goalspec scope amend --allow <glob> [--allow <glob> ...] --reason <text>
  goalspec scope effective

Commands:
  amend      Record a human-approved expansion of the current allowed scope.
  effective  Print effective allowed_paths and forbidden_paths.
EOF
}

cmd="${1:-}"
[ $# -gt 0 ] && shift || true
case "$cmd" in
  amend)
    reason=""
    allows=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --allow)
          [ $# -ge 2 ] || { usage; exit 2; }
          allows+=("$2")
          shift 2
          ;;
        --reason)
          [ $# -ge 2 ] || { usage; exit 2; }
          reason="$2"
          shift 2
          ;;
        *)
          echo "scope amend: unknown argument '$1'" >&2
          usage
          exit 2
          ;;
      esac
    done
    goalspec_scope_amend_allow "$reason" "${allows[@]}"
    ;;
  effective)
    echo "allowed_paths:"
    goalspec_scope_allowed_patterns | sort -u | sed 's/^/  - /'
    echo "forbidden_paths:"
    goalspec_scope_forbidden_patterns | sort -u | sed 's/^/  - /'
    echo "scope_hash: $(goalspec_scope_hash)"
    ;;
  *)
    usage
    exit 2
    ;;
esac
