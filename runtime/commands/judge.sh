#!/usr/bin/env bash
# judge.sh — Master verdict prompt / apply (goal-driven: verdicts anchor on
# Criteria, not work units; enhance.md §12).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

sub="${1:-}"; shift || true
cf="$GOALSPEC_ROOT/active/contract.yaml"
ef="$GOALSPEC_ROOT/active/evidence.yaml"
vf="$GOALSPEC_ROOT/active/verdict.yaml"

case "$sub" in
  prompt)
    crit="${1:-}"
    cat <<EOF
# Master verdict prompt (fresh context)

You are the MASTER. Do not read any Subagent conversation. Read ONLY:
  - .goalspec/active/contract.yaml
  - .goalspec/active/evidence.yaml
  - .goalspec/active/trace.yaml
  - .goalspec/active/state.yaml
  - .goalspec/active/regressions.yaml
  - .goalspec/artifacts/**
${crit:+  - criterion of interest: $crit}

Verify the relevant Criteria against the evidence. Rules:
  - context MUST be fresh; do not trust the Subagent's self-report.
  - the verdict's contract_hash MUST equal the current frozen contract hash.
  - the verdict's evidence_hash MUST equal the current evidence.yaml hash.
  - all referenced evidence_ids and criteria_refs must exist.
  - a 'pass' verdict MUST cite evidence whose runtime_boundary and facets meet
    the criterion's evidence_requirement_refs.
  - If the criterion cannot be proven, emit fail/insufficient/blocked/stale/
    reopen_required as appropriate (never pretend pass).

Emit a YAML document with these fields:
  criteria_ref: "<CRIT-...>"
  evidence_refs: [EV-...]
  contract_hash: "<sha256:...>"
  evidence_hash: "<sha256:...>"
  verdict: pass | fail | insufficient | blocked | stale | reopen_required
  reason: "..."
  context: fresh
  evaluated_by: master
EOF
    ;;
  apply)
    file="${1:-}"
    [ -n "$file" ] || { echo "usage: goalspec judge apply <verdict.yaml>" >&2; exit 2; }
    [ -f "$file" ] || { echo "verdict file not found: $file" >&2; exit 1; }
    if ! errs="$(goalspec_schema_verdict_file "$file" 2>&1 >/dev/null)"; then
      echo "$errs" >&2
      exit 1
    fi
    # Validate context:fresh
    ctx="$(yq e '.context' "$file")"
    [ "$ctx" = "fresh" ] || { echo "judge apply: context must be 'fresh' (got '$ctx')" >&2; exit 1; }
    # contract must be frozen
    [ "$(yq e '.status' "$cf")" = "frozen" ] || { echo "judge apply: contract not frozen" >&2; exit 1; }
    # hash must match
    cur_chash="$(goalspec_contract_hash)"
    v_chash="$(yq e '.contract_hash' "$file")"
    [ "$cur_chash" = "$v_chash" ] || { echo "judge apply: contract_hash mismatch (verdict=$v_chash current=$cur_chash) — stale" >&2; exit 1; }
    cur_ehash="$(goalspec_evidence_hash)"
    v_ehash="$(yq e '.evidence_hash' "$file")"
    [ "$cur_ehash" = "$v_ehash" ] || { echo "judge apply: evidence_hash mismatch (verdict=$v_ehash current=$cur_ehash) — re-judge" >&2; exit 1; }
    # referenced criteria + evidence must exist
    crit="$(yq e '.criteria_ref' "$file")"
    if ! yq e ".criteria[] | select(.id == \"$crit\")" "$cf" >/dev/null 2>&1 || [ -z "$(yq e ".criteria[] | select(.id == \"$crit\") | .id" "$cf")" ]; then
      echo "judge apply: criteria_ref $crit not found in contract" >&2; exit 1
    fi
    # each evidence_ref must exist
    n="$(yq e '.evidence_refs | length' "$file")"
    i=0
    while [ "$i" -lt "$n" ]; do
      er="$(yq e ".evidence_refs[$i]" "$file")"
      if ! yq e ".evidence[] | select(.id == \"$er\") | .id" "$ef" 2>/dev/null | grep -q .; then
        echo "judge apply: evidence_ref $er not found in evidence.yaml" >&2; exit 1
      fi
      i=$((i+1))
    done
    verdict="$(yq e '.verdict' "$file")"
    # If verdict=pass, the cited evidence must satisfy the criterion's
    # evidence_requirement_refs (criteria carry the requirements now).
    if [ "$verdict" = "pass" ]; then
      reqs="$(yq e ".criteria[] | select(.id == \"$crit\") | .evidence_requirement_refs.[]" "$cf")"
      # Collect evidence_requirement_refs actually cited by the evidence used.
      cited_reqs=""
      i=0
      while [ "$i" -lt "$n" ]; do
        er="$(yq e ".evidence_refs[$i]" "$file")"
        cited_reqs="${cited_reqs}$(yq e ".evidence[] | select(.id == \"$er\") | .evidence_requirement_refs.[]" "$ef" 2>/dev/null)"$'\n'
        i=$((i+1))
      done
      missing=""
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if ! printf '%s\n' "$cited_reqs" | grep -qx "$r"; then
          missing="${missing}${r} "
        fi
      done <<<"$reqs"
      if [ -n "$missing" ]; then
        echo "judge apply: pass verdict does not cite evidence satisfying required evidence requirements: $missing" >&2
        exit 1
      fi
    fi
    # Append to verdict.yaml
    goalspec_init_list_file "$vf" verdicts
    tmp="$(mktemp)"
    # Copy the verdict file with judged_at injected.
    yq ".judged_at = \"$(goalspec_now)\"" "$file" > "$tmp"
    yq e -i ".verdicts += load(\"$tmp\")" "$vf"
    /bin/rm -f "$tmp"
    # Update evidence_hash snapshot in state to track future stale.
    yq e -i ".evidence_hash = \"$(goalspec_evidence_hash)\"" "$GOALSPEC_ROOT/active/state.yaml"
    echo "verdict applied: $verdict (crit=$crit)"
    ;;
  *)
    echo "usage: goalspec judge prompt|apply" >&2; exit 2
    ;;
esac
