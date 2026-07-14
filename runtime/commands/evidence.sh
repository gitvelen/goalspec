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
  # When produced_by: subagent, 'goalspec evidence audit' (below) requires a
  # non-empty subagent_transcript_path pointing at the subagent transcript —
  # so the Master can re-read the producer's context. The default 'evidence
  # check' does NOT enforce this (backward compatible); opt in via 'audit'
  # when role separation matters (e.g. large goals where the Master may be
  # tempted to write evidence directly).
  # subagent_transcript_path: .claude/.../tasks/<id>.jsonl
  produced_at: "$(goalspec_now)"
  residual_risk:
    level: none
    notes: ""
  # coverage_claims (OPTIONAL, anti-silent-pass): declare the routes/states this
  # evidence actually exercises. When present + reproducible:true, the sensor
  # greps the re-run output for a `GOALSPEC_COVERED: <route>` marker per route
  # and rejects the pass verdict if any is missing — so a test that runs on the
  # wrong route (e.g. an auth redirect) cannot pass silently. Emit the marker in
  # the spec AFTER the route-specific assertion:
  #   await page.goto("/governance/overview");
  #   await expect(header).toBeVisible();
  #   console.log("GOALSPEC_COVERED: /governance/overview");
  # coverage_claims:
  #   - route: "/governance/overview"
  #     state: "full"
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
  audit)
    # Opt-in stricter check (velentrade v0006: A1 subagent was killed on
    # session exit; the Master wrote the code directly but evidence still
    # claimed produced_by: subagent, with no transcript to re-read). Runs
    # every 'check' rule PLUS: produced_by=subagent requires a non-empty
    # subagent_transcript_path, else the entry must honestly say
    # produced_by: master. The default 'check' is unchanged so old goals and
    # existing fixtures (goalc_30/79/52) are not broken; operators opt in
    # when role-separation integrity matters.
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
      if ! goalspec_schema_evidence_entry "$id" 2>&1; then
        errs=$((errs+1))
      fi
      pb="$(yq e ".evidence[$i].produced_by // \"\"" "$ef")"
      if [ "$pb" = "subagent" ]; then
        tp="$(yq e ".evidence[$i].subagent_transcript_path // \"\"" "$ef")"
        if [ -z "$tp" ] || [ "$tp" = "null" ]; then
          echo "evidence $id: produced_by=subagent requires subagent_transcript_path (Master 直写须改 produced_by: master)" >&2
          errs=$((errs+1))
        fi
      fi
      i=$((i+1))
    done
    [ "$errs" -eq 0 ] && echo "evidence audit: $n entries, role separation verifiable"
    [ "$errs" -eq 0 ]
    ;;
  *)
    echo "usage: goalspec evidence template|check|audit" >&2; exit 2
    ;;
esac
