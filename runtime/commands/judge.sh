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
    state_file="$GOALSPEC_ROOT/active/state.yaml"
    state="$(yq e '.status // "no_goal"' "$state_file" 2>/dev/null || echo "no_goal")"
    [ "$state" != "reopen_required" ] || { echo "judge apply: state is reopen_required; re-review, re-approve, and freeze the revised goal/contract before judging again" >&2; exit 1; }
    # run-loop stop-loss: refuse verdicts once the loop is capped (Step 05).
    [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" != "capped" ] \
      || { echo "judge apply: run-loop is capped (reached max_iterations); run /goalspec close if Criteria are met, or /goalspec reopen to reset" >&2; exit 1; }
    # run-loop no-progress: refuse verdicts once the loop is stalled — the
    # verdict fingerprint and evidence have not changed for stall_threshold rounds,
    # so further Subagent iteration cannot help. Reopen the spec or close if met.
    [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" != "stalled" ] \
      || { echo "judge apply: run-loop is stalled (no progress for stall_threshold rounds); run /goalspec reopen to revise the spec, or /goalspec close if Criteria are met" >&2; exit 1; }
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
      # Tier 2: sensor verification. A pass verdict on reproducible evidence
      # must be confirmable by re-running the evidence's command now — profile
      # test/lint/typecheck only run at close, so without this a pass verdict
      # can rest on the Subagent's self-reported exit_code. Only reproducible
      # evidence is re-run (side-effect safety); negative verdicts never reach
      # here. On failure the verdict is rejected (not auto-downgraded) so the
      # Master stays the sole verdict author.
      i=0
      while [ "$i" -lt "$n" ]; do
        er="$(yq e ".evidence_refs[$i]" "$file")"
        if ! sensor_err="$(goalspec_sensor_verify_evidence "$er" 2>&1 1>/dev/null)"; then
          echo "judge apply: pass verdict rejected — $sensor_err" >&2
          exit 1
        fi
        i=$((i+1))
      done
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
    # run-loop stop-loss: each Master verdict is one round of the run-loop that
    # /goalspec run drives. Count it; cap at profile.run_loop.max_iterations
    # (default 8). At the cap the loop is marked capped so /goalspec run and
    # further judge apply refuse until a human /goalspec close or /goalspec
    # reopen resets it (Step 05 / Akshy: exit conditions decided before running).
    iter="$(yq e '.run_loop.iteration // 0' "$state_file")"
    iter=$((iter+1))
    max_iter="$(goalspec_delivery_profile_value '.run_loop.max_iterations' '8')"
    yq e -i ".run_loop.iteration = $iter | .run_loop.last_at = \"$(goalspec_now)\"" "$state_file"
    echo "verdict applied: $verdict (crit=$crit)"
    if [ "$iter" -ge "$max_iter" ]; then
      yq e -i '.run_loop.last_outcome = "capped"' "$state_file"
      echo "LOOP_CAPPED: run-loop reached max_iterations=$max_iter; further /goalspec run and judge apply will refuse until /goalspec close or /goalspec reopen" >&2
    else
      yq e -i '.run_loop.last_outcome = "step"' "$state_file"
    fi
    # No-progress detection (stalled): independent of the iteration cap. Fires
    # when the verdict fingerprint and evidence_hash are both unchanged across N
    # consecutive judge-apply rounds — the loop is spinning without advancing
    # any criterion verdict (Oracle: no-progress detection; Ralph Wiggum guard).
    # Skipped when the cap already fired (cap takes precedence) and exempted when
    # all required criteria already pass (the loop is done, not stalled).
    if [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" != "capped" ]; then
      fp="$(goalspec_close_verdict_fingerprint)"
      ehash="$(goalspec_evidence_hash)"
      prev_fp="$(yq e '.run_loop.last_fingerprint // ""' "$state_file")"
      prev_ehash="$(yq e '.run_loop.last_evidence_hash // ""' "$state_file")"
      if [ "$fp" = "$prev_fp" ] && [ "$ehash" = "$prev_ehash" ]; then
        stall_count="$(yq e '.run_loop.stall_count // 0' "$state_file")"
        stall_count=$((stall_count+1))
      else
        stall_count=0
      fi
      yq e -i ".run_loop.stall_count = $stall_count | .run_loop.last_fingerprint = \"$fp\" | .run_loop.last_evidence_hash = \"$ehash\"" "$state_file"
      stall_threshold="$(goalspec_delivery_profile_value '.run_loop.stall_threshold' '3')"
      if [ "$stall_count" -ge "$stall_threshold" ] && ! goalspec_close_all_required_pass; then
        yq e -i '.run_loop.last_outcome = "stalled"' "$state_file"
        echo "LOOP_STALLED: run-loop made no progress for $stall_count consecutive rounds (verdict fingerprint and evidence unchanged); likely a spec defect — run /goalspec reopen to revise, or /goalspec close if Criteria are actually met" >&2
      fi
    fi
    # Tier 1 (observability) + Self-Harness (advisory). Append one trace entry
    # for this round, recompute the derived trajectory, and — on a confirmed
    # failure — emit an advisory improvement candidate (idempotent, human-gated).
    t1_outcome="$(yq e '.run_loop.last_outcome // "continue"' "$state_file")"
    t1_why="iteration $iter < max_iterations=$max_iter"
    case "$t1_outcome" in
      capped) t1_why="iteration $iter >= max_iterations=$max_iter" ;;
      stalled) t1_why="no progress for $stall_count consecutive rounds (verdict fingerprint + evidence unchanged)" ;;
      step|"") t1_outcome="continue" ;;
    esac
    goalspec_trace_append "$crit" "$verdict" "$(yq e '.reason' "$file")" "$t1_outcome" "$t1_why"
    goalspec_trajectory_recompute
    case "$t1_outcome" in
      capped|stalled) goalspec_harness_emit_candidate "$t1_outcome" ;;
    esac
    ;;
  *)
    echo "usage: goalspec judge prompt|apply" >&2; exit 2
    ;;
esac
