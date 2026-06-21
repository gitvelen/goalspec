#!/usr/bin/env bash
# trace.sh — Loop Engineering observability + Self-Harness advisory helpers.
# Sourced after close.sh / git_delivery.sh (uses goalspec_close_* and
# goalspec_delivery_profile_value). Three concerns live here:
#   1. trace.yaml       — one entry per judge-apply round (the audit trail).
#   2. run_loop.trajectory — DERIVED summary of tried/failed/blocker/next.
#   3. harness-improvement-candidate.yaml — advisory skeleton emitted on cap/stall.
#   4. loop-contract render — read-only 11-item view assembled for `status`.

# Append one trace entry for the judge-apply round just completed.
# args: <criterion_ref> <verdict> <reason> <stop_outcome> <stop_why>
goalspec_trace_append() {
  local crit="$1" verdict="$2" reason="$3" stop_outcome="$4" stop_why="$5"
  local tf="$GOALSPEC_ROOT/active/trace.yaml" sf="$GOALSPEC_ROOT/active/state.yaml"
  local iter chash phash judged_at cur_ehash prev_ehash diff_ids diff_json tmp
  iter="$(yq e '.run_loop.iteration // 0' "$sf")"
  chash="$(goalspec_contract_hash)"
  phash="$(yq e '.prompt_hash // ""' "$sf")"
  judged_at="$(goalspec_now)"
  # evidence_diff (approximation): when the evidence_hash moved this round,
  # list the current EV ids. Exact per-EV diff is out of scope for the minimum.
  cur_ehash="$(goalspec_evidence_hash)"
  prev_ehash="$(yq e '.run_loop.last_evidence_hash // ""' "$sf")"
  diff_ids=""
  if [ "$cur_ehash" != "$prev_ehash" ] && [ -n "$prev_ehash" ]; then
    diff_ids="$(yq e '.evidence[].id' "$GOALSPEC_ROOT/active/evidence.yaml" 2>/dev/null || true)"
  fi
  if [ -n "$diff_ids" ]; then
    diff_json="$(printf '%s\n' "$diff_ids" | grep -v '^$' | sed 's/.*/"&"/' | paste -sd, - | sed 's/^/[/; s/$/]/')"
  else
    diff_json="[]"
  fi
  goalspec_init_list_file "$tf" traces
  tmp="$(mktemp)"
  reason="$reason" diff_json="$diff_json" iter="$iter" ja="$judged_at" crit="$crit" \
  verdict="$verdict" outcome="$stop_outcome" why="$stop_why" chash="$chash" phash="$phash" \
    yq -n '.iteration = (strenv(iter) | tonumber)
         | .judged_at = strenv(ja)
         | .criterion_ref = strenv(crit)
         | .verdict = strenv(verdict)
         | .master_reasoning = strenv(reason)
         | .evidence_diff = (strenv(diff_json) | from_json)
         | .stop_check.outcome = strenv(outcome)
         | .stop_check.why = strenv(why)
         | .contract_hash = strenv(chash)
         | .prompt_hash = strenv(phash)' > "$tmp"
  yq e -i ".traces += load(\"$tmp\")" "$tf"
  /bin/rm -f "$tmp"
}

# Recompute the DERIVED trajectory summary in state.run_loop.trajectory from
# verdict.yaml + contract. Pure derivation; no Master input.
goalspec_trajectory_recompute() {
  local sf="$GOALSPEC_ROOT/active/state.yaml" cid latest reason
  local tried="" failed="" blocker="" next_step=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    latest="$(goalspec_close_latest_verdict_field "$cid" verdict)"
    if [ -z "$latest" ]; then
      [ -z "$next_step" ] && next_step="$cid"
      continue
    fi
    tried="${tried}${cid}=${latest}|"
    case "$latest" in
      pass) ;;
      *)
        failed="${failed}${cid}=${latest}|"
        if [ -z "$blocker" ]; then
          reason="$(goalspec_close_latest_verdict_field "$cid" reason)"
          blocker="${cid}: ${latest} - ${reason}"
        fi
        [ -z "$next_step" ] && next_step="$cid"
        ;;
    esac
  done <<<"$(goalspec_close_required_criteria_ids)"
  tried="$tried" failed="$failed" blocker="$blocker" next_step="$next_step" \
    yq e -i '.run_loop.trajectory.tried_paths = (strenv(tried) | split("|") | map(select(. != "")))
          | .run_loop.trajectory.failed_approaches = (strenv(failed) | split("|") | map(select(. != "")))
          | .run_loop.trajectory.current_blocker = strenv(blocker)
          | .run_loop.trajectory.next_step = strenv(next_step)' "$sf"
}

# Emit the advisory Self-Harness candidate skeleton on a confirmed failure
# (capped/stalled). Idempotent: one candidate per active goal. NEVER fills
# proposed_target/prediction and NEVER sets promoted — promotion is human-gated.
# args: <failure_kind>  (capped | stalled)
goalspec_harness_emit_candidate() {
  local kind="$1"
  local cand="$GOALSPEC_ROOT/active/harness-improvement-candidate.yaml"
  # Idempotent per active goal. init copies the template into active/ (so the
  # file always exists with emitted_at: null); a real emit sets emitted_at.
  # Skip only if a candidate was already emitted for this goal.
  if [ -f "$cand" ]; then
    local prev_at
    prev_at="$(yq e '.emitted_at // ""' "$cand" 2>/dev/null || echo "")"
    [ -n "$prev_at" ] && [ "$prev_at" != "null" ] && return 0
  fi
  local sf="$GOALSPEC_ROOT/active/state.yaml" tf="$GOALSPEC_ROOT/active/trace.yaml"
  local iter goal_id goal_type chash phash mhash cid v failing last_crit last_why failing_json ja
  iter="$(yq e '.run_loop.iteration // 0' "$sf")"
  goal_id="$(yq e '.active_goal_id // ""' "$sf")"
  goal_type="$(awk '/^## .*Intent/ { in_intent=1; next } /^## / && in_intent { exit } in_intent && NF { print; exit }' "$GOALSPEC_ROOT/active/goal.md" 2>/dev/null || true)"
  chash="$(goalspec_contract_hash)"
  phash="$(yq e '.prompt_hash // ""' "$sf")"
  mhash="$(goalspec_hash_file "$GOALSPEC_ROOT/runtime/templates/ai/master.md")"
  failing=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    v="$(goalspec_close_latest_verdict_field "$cid" verdict)"
    case "$v" in pass|"") ;; *) failing="${failing}${cid}|";; esac
  done <<<"$(goalspec_close_required_criteria_ids)"
  last_crit="$(yq e '.traces[-1].criterion_ref // ""' "$tf" 2>/dev/null || true)"
  last_why="$(yq e '.traces[-1].stop_check.why // ""' "$tf" 2>/dev/null || true)"
  if [ -n "$failing" ]; then
    failing_json="$(printf '%s' "$failing" | tr '|' '\n' | grep -v '^$' | sed 's/.*/"&"/' | paste -sd, - | sed 's/^/[/; s/$/]/')"
  else
    failing_json="[]"
  fi
  ja="$(goalspec_now)"
  cp "$GOALSPEC_ROOT/runtime/templates/active/harness-improvement-candidate.yaml" "$cand"
  gid="$goal_id" gt="$goal_type" fj="$failing_json" iter="$iter" rc="$last_crit" rr="$last_why" \
  chash="$chash" phash="$phash" mhash="$mhash" ja="$ja" kind="$kind" \
    yq e -i '.status = "proposed"
          | .emitted_at = strenv(ja)
          | .failure_kind = strenv(kind)
          | .task_signature.goal_id = strenv(gid)
          | .task_signature.goal_type = strenv(gt)
          | .task_signature.repeatedly_failing_criteria = (strenv(fj) | from_json)
          | .failure_step.iteration = (strenv(iter) | tonumber)
          | .failure_step.refused_criterion = strenv(rc)
          | .failure_step.validator_reason = strenv(rr)
          | .rule_version.contract_hash = strenv(chash)
          | .rule_version.prompt_hash = strenv(phash)
          | .rule_version.master_md_hash = strenv(mhash)' "$cand"
}

# Render the 11-item loop contract as a read-only view. Prints key:value lines
# to stdout. Assembles from goal.md/contract.yaml/profile.yaml/state.yaml;
# writes nothing to disk.
goalspec_loop_contract_render() {
  local sf="$GOALSPEC_ROOT/active/state.yaml" cf="$GOALSPEC_ROOT/active/contract.yaml"
  local pf="$GOALSPEC_ROOT/project/profile.yaml" gf="$GOALSPEC_ROOT/active/goal.md"
  local name goal scope tools max_iter stall_thresh iter last_outcome traj
  name="$(yq e '.active_goal_id // "unnamed"' "$sf")"
  goal="$(awk '/^## .*Intent/ { in_intent=1; next } /^## / && in_intent { exit } in_intent && NF { print; exit }' "$gf" 2>/dev/null || echo "")"
  scope="$(yq e -o=t '.allowed_paths[]' "$cf" 2>/dev/null | paste -sd, -)"
  tools="$(yq e '(.commands.test // []) + (.commands.build // []) + (.commands.lint // []) + (.commands.typecheck // []) | join(", ")' "$pf" 2>/dev/null || echo "")"
  max_iter="$(goalspec_delivery_profile_value '.run_loop.max_iterations' '8')"
  stall_thresh="$(goalspec_delivery_profile_value '.run_loop.stall_threshold' '3')"
  iter="$(yq e '.run_loop.iteration // 0' "$sf")"
  last_outcome="$(yq e '.run_loop.last_outcome // "null"' "$sf")"
  traj="$(yq e -o=json -I=0 '.run_loop.trajectory // {}' "$sf" 2>/dev/null || echo "{}")"
  echo "name: $name"
  echo "trigger: /goalspec run (state=$(yq e '.status // "no_goal"' "$sf"))"
  echo "goal: ${goal:-none}"
  echo "input: contract.yaml (frozen), evidence.yaml, verdict.yaml, trace.yaml"
  echo "scope: ${scope:-none}"
  echo "tools: ${tools:-none}"
  echo "verification: profile.commands.{test,build,lint,typecheck} at /goalspec close; sensor re-run of reproducible evidence at judge apply"
  echo "stop: max_iterations=$max_iter, stall_threshold=$stall_thresh, judgment-kind gate, all-required-pass"
  echo "escalation: /goalspec reopen <reason> (capped -> close-or-reopen; stalled -> reopen), /goalspec close (human gate)"
  echo "state: iteration=$iter, last_outcome=$last_outcome, trajectory=$traj"
  echo "cleanup: close archives active/ to history/vNNNN/, applies memory-patch, resets run_loop"
}
