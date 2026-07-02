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
  - the verdict's evidence_hash MUST equal the current evidence.yaml hash at
    judge-apply time; later close freshness is based on evidence_basis_hash for
    the cited evidence_refs.
  - all referenced evidence_ids and criteria_refs must exist.
  - a 'pass' verdict MUST cite evidence whose runtime_boundary and facets meet
    the criterion's evidence_requirement_refs.
  - evidence_requirement_refs are necessary but NOT sufficient: they prove the
    evidence type is present, not that every statement claim is satisfied.
  - If the criterion cannot be proven, emit fail/insufficient/blocked/stale/
    reopen_required as appropriate (never pretend pass).

Before emitting a pass verdict, perform Criteria Coverage Audit:
  1. Statement decomposition — split criterion.statement into atomic claims,
     including fields, states, samples, interactions, failure states, history,
     visual requirements, LLM requirements, persistence, and must-not clauses.
  2. Evidence mapping — cite evidence id(s) for each atomic claim. A claim with
     no supporting evidence id is not proven.
  3. Evidence strength classification — classify each cited evidence as real
     runtime, browser runtime, API runtime, integration test, unit test,
     fixture, mock, static assertion, or manual observation.
  4. Sufficiency check — decide whether the evidence strength is enough for the
     claim. Fixture/mock evidence cannot masquerade as real runtime evidence;
     missing-state samples cannot prove full-data states; unit tests alone do
     not automatically prove user-visible interaction completeness.
  5. Pass rule — if any atomic claim lacks sufficient evidence, do not pass;
     emit insufficient/fail/blocked/stale/reopen_required instead.

Emit a YAML document with these fields:
  criteria_ref: "<CRIT-...>"
  evidence_refs: [EV-...]
  contract_hash: "<sha256:...>"
  evidence_hash: "<sha256:...>"
  evidence_basis_hash: "<sha256:...>"  # hash of cited evidence_refs only
  verdict: pass | fail | insufficient | blocked | stale | reopen_required
  # criterion_hash and goal_hash are injected automatically at apply time; you
  # do NOT emit them. They anchor scoped freshness so a verdict stays valid
  # across a reopen that doesn't touch its criterion or the goal.
  reason: |-
    Coverage audit:
    - claim: "..."
      evidence: [EV-...]
      sufficiency: sufficient | insufficient | partial
      why: "..."
    conclusion: "..."
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
    # Only current stalled states block. Older releases stored a coarser
    # fingerprint, so a stale-pass basis may become obsolete after refreeze.
    if [ "$(yq e '.run_loop.last_outcome // ""' "$state_file")" = "stalled" ]; then
      if goalspec_run_loop_stalled_current; then
        echo "judge apply: run-loop is stalled (no progress for stall_threshold rounds); run /goalspec reopen to revise the spec, or /goalspec close if Criteria are met" >&2
        exit 1
      fi
      goalspec_run_loop_clear_obsolete_stalled
    fi
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
    basis_refs="$(yq e '.evidence_refs[]' "$file" 2>/dev/null || true)"
    cur_basis="$(printf '%s\n' "$basis_refs" | goalspec_evidence_basis_hash 2>/dev/null || true)"
    [ -n "$cur_basis" ] || { echo "judge apply: could not compute evidence_basis_hash" >&2; exit 1; }
    v_basis="$(yq e '.evidence_basis_hash // ""' "$file")"
    if [ -n "$v_basis" ] && [ "$v_basis" != "null" ] && [ "$v_basis" != "$cur_basis" ]; then
      echo "judge apply: evidence_basis_hash mismatch (verdict=$v_basis current=$cur_basis) — re-judge" >&2; exit 1
    fi
    verdict="$(yq e '.verdict' "$file")"
    # A pass verdict must show its semantic coverage work, not just say tests
    # passed. This is intentionally a lightweight format guard; the Master still
    # owns the semantic judgment, while the CLI prevents one-line pass reasons.
    if [ "$verdict" = "pass" ]; then
      reason="$(yq e '.reason // ""' "$file")"
      missing_audit=""
      for token in 'Coverage audit:' 'claim' 'evidence' 'sufficiency' 'conclusion'; do
        if ! printf '%s\n' "$reason" | grep -q "$token"; then
          missing_audit="${missing_audit}${token} "
        fi
      done
      if [ -n "$missing_audit" ]; then
        echo "judge apply: pass verdict reason missing Criteria Coverage Audit fields: $missing_audit" >&2
        exit 1
      fi
    fi
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
        e_chash="$(yq e ".evidence[] | select(.id == \"$er\") | .contract_hash // \"\"" "$ef" 2>/dev/null || true)"
        if [ "$e_chash" != "$cur_chash" ]; then
          echo "judge apply: pass verdict cites stale evidence $er (evidence_contract=$e_chash current=$cur_chash)" >&2
          exit 1
        fi
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
    # Copy the verdict file with judged_at, the selective evidence basis, and the
    # scoped freshness anchors injected. criterion_hash + goal_hash let close-time
    # freshness be per-criterion (scoped-reopen): a verdict stays fresh across a
    # reopen that doesn't touch its criterion or the goal. Legacy verdicts that
    # predate these fields fall back to whole-contract freshness in close.sh.
    crit_h="$(goalspec_criterion_hash "$crit")"
    goal_h="$(goalspec_goal_hash)"
    yq ".judged_at = \"$(goalspec_now)\" | .evidence_basis_hash = \"$cur_basis\" | .criterion_hash = \"$crit_h\" | .goal_hash = \"$goal_h\"" "$file" > "$tmp"
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
    # Default 40 (was 8): a goal needs >= one verdict per required criterion, so
    # 8 capped almost any non-trivial first run. trace.sh renders the same value
    # to the model's loop contract — keep the two defaults identical so the
    # rendered budget matches the enforced one. Projects with large goals set
    # their own max_iterations. The mass-re-judge that blew the cap in the v0004
    # transcript is cured at the root by scoped-reopen (per-criterion freshness),
    # not by raising this number indefinitely.
    max_iter="$(goalspec_delivery_profile_value '.run_loop.max_iterations' '40')"
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
