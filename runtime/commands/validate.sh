#!/usr/bin/env bash
# validate.sh — `goalspec validate` entry point.
# Collect-all validation of active/ artifacts (does not fail-fast). Reuses the
# returning schema/stale/hash helpers via lib/validate.sh and adds cross-file
# reference integrity under --strict. See `goalspec validate --help`.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

target="all"
strict="0"
json="0"

usage() {
  cat <<'EOF' >&2
usage: goalspec validate [goal|contract|evidence|verdict|state|intake|all]
                         [--strict] [--json]

Check the structural integrity of .goalspec/active/ in collect mode (reports
every finding instead of stopping at the first). Exit 0 when clean, 1 on any
error (or on any warning under --strict).

Targets (default: all):
  goal       goal.md required sections
  contract   contract.yaml freeze schema
  evidence   evidence.yaml parse + contract_hash freshness
  verdict    verdict.yaml per-entry required fields + verdict enum
  state      state.yaml status + staleness (warnings)
  intake     constraint-suggestions.yaml parse
  all        all of the above, plus completion-readiness preview

Flags:
  --strict   also run cross-file reference integrity (dangling criteria /
             evidence refs) and treat warnings as errors
  --json     machine-readable output (CI-friendly): {ok,errors,warnings,findings}
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --strict)  strict="1"; shift ;;
    --json)    json="1"; shift ;;
    --target)  [ $# -ge 2 ] || { usage; exit 2; }; target="$2"; shift 2 ;;
    goal|contract|evidence|verdict|state|intake|all) target="$1"; shift ;;
    *) echo "validate: unknown argument '$1' (see --help)" >&2; exit 2 ;;
  esac
done

goalspec_validate_run "$target" "$strict"
goalspec_validate_emit "$json"
goalspec_validate_exit_code "$strict"
