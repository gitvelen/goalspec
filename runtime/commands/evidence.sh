#!/usr/bin/env bash
# evidence.sh — template / check evidence entries (goal-driven: evidence binds
# to Criteria; enhance.md §12).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

sub="${1:-}"; shift || true
ef="$GOALSPEC_ROOT/active/evidence.yaml"
cf="$GOALSPEC_ROOT/active/contract.yaml"

case "$sub" in
  template)
    crit="${1:-}"
    [ -n "$crit" ] || { echo "usage: goalspec evidence template <criteria_id>" >&2; exit 2; }
    # Pull evidence_requirement_refs for this criterion.
    ereqs="$(yq e ".criteria[] | select(.id == \"$crit\") | .evidence_requirement_refs.[]" "$cf" 2>/dev/null)"
    chash="$(goalspec_contract_hash)"
    n="$(yq e '.evidence | length' "$ef" 2>/dev/null || echo 0)"
    eid="EV-$(printf '%03d' $((n+1)))"
    cat <<EOF
# Evidence entry (Subagent fills in command, exit_code, artifact_paths).
# Append to .goalspec/active/evidence.yaml under 'evidence:'.
- id: $eid
  contract_hash: "$chash"
  criteria_refs: ["$crit"]
  evidence_requirement_refs: [$(echo "$ereqs" | sed 's/^/"/; s/$/",/' | tr -d '\n' | sed 's/,$//')]
  command: "<command that produced the fact>"
  exit_code: 0
  artifact_paths: []
  provider_source: not_required
  runtime_boundary: browser
  persistence: memory
  completion_level: integrated_runtime
  reproducible: true
  # sensor_scope: artifact_existence_only  # required iff reproducible:true AND (completion_level=manual_observation OR runtime_boundary=manual)
  produced_by: subagent
  produced_at: "$(goalspec_now)"
  residual_risk:
    level: none
    notes: ""
EOF
    ;;
  check)
    [ -f "$ef" ] || { echo "evidence.yaml not found" >&2; exit 1; }
    errs=0
    n="$(yq e '.evidence | length' "$ef")"
    i=0
    chash="$(goalspec_contract_hash)"
    while [ "$i" -lt "$n" ]; do
      id="$(yq e ".evidence[$i].id" "$ef")"
      eh="$(yq e ".evidence[$i].contract_hash // \"\"" "$ef")"
      if [ -n "$eh" ] && [ "$eh" != "$chash" ]; then
        echo "evidence $id: contract_hash does not match current contract (stale)" >&2
        errs=$((errs+1))
      fi
      # Tier 2: reproducible evidence must carry a command the sensor can re-run.
      if ! goalspec_schema_evidence_entry "$id" 2>&1; then
        errs=$((errs+1))
      fi
      i=$((i+1))
    done
    [ "$errs" -eq 0 ] && echo "evidence: $n entries, all contract_hash current"
    [ "$errs" -eq 0 ]
    ;;
  *)
    echo "usage: goalspec evidence template|check" >&2; exit 2
    ;;
esac
