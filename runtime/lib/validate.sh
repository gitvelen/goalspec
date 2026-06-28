#!/usr/bin/env bash
# validate.sh — collect-all validation orchestrator for `goalspec validate`.
#
# Design: the framework already has returning (non-exiting) schema/stale/hash/
# scope helpers in lib/schema.sh, lib/stale.sh, lib/hash.sh, lib/scope.sh. This
# file is a thin orchestrator that runs them in COLLECT mode (records every
# finding instead of fail-fast) and adds the one genuinely-missing capability:
# cross-file reference integrity (goalspec_validate_integrity).
#
# Severity model:
#   error   -> structural corruption (schema violation, dangling reference,
#              unparseable artifact). Always causes exit 1.
#   warning -> informational lifecycle state (staleness, completion-readiness
#              gaps, orphan evidence requirements). Exit 0 unless --strict.
#
# Findings are stored in GOALSPEC_VALIDATE_FINDINGS as TAB-separated
# "severity<TAB>target<TAB>check<TAB>message" records (message forced single-line).

GOALSPEC_VALIDATE_FINDINGS=()
GOALSPEC_VALIDATE_STRICT="0"

# Append one finding. Remaining args after check are the message (joined).
goalspec_validate_record() {
  local sev="$1" target="$2" check="$3"; shift 3
  local msg="$*"
  # Collapse any embedded newlines (schema helpers may print multi-line stderr)
  # so every finding is a single line for both human and JSON output.
  msg="${msg//$'\n'/; }"
  GOALSPEC_VALIDATE_FINDINGS+=("$(printf '%s\t%s\t%s\t%s' "$sev" "$target" "$check" "$msg")")
}

# Run a RETURNING helper (prints errors to stderr, returns 0/1) and record its
# stderr as a finding on failure. Never exits.
goalspec_validate_run_check() {
  local sev="$1" target="$2" check="$3"; shift 3
  local err rc
  err="$("$@" 2>&1 1>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ -n "$err" ] || err="$check failed"
  goalspec_validate_record "$sev" "$target" "$check" "$err"
}

# true (0) if $1 appears as a whole line in $2
goalspec_validate_in_list() {
  local needle="$1" haystack="$2"
  [ -n "$needle" ] && [ -n "$haystack" ] && printf '%s\n' "$haystack" | grep -qxF "$needle"
}

# --- per-target checks -------------------------------------------------------

goalspec_validate_goal() {
  local gf="$GOALSPEC_ROOT/active/goal.md"
  [ -f "$gf" ] || { goalspec_validate_record error goal presence "goal.md not found"; return; }
  goalspec_validate_run_check error goal schema goalspec_schema_goal_md
  # --strict: enforce the four sections NOT already covered by the base check
  # (which validates Intent/Narrative/Success Model/Scope/Risk Scan).
  if [ "$GOALSPEC_VALIDATE_STRICT" = "1" ]; then
    local h
    for h in "Goal Constraints" "Sources and Decisions" "Open Questions" \
             "Reopen Triggers"; do
      grep -q "## .*${h}" "$gf" || \
        goalspec_validate_record error goal sections "goal.md missing section: $h"
    done
  fi
}

goalspec_validate_contract() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || return  # contract is a placeholder until compile; absent is fine early on
  if ! yq e '.status' "$cf" >/dev/null 2>&1; then
    goalspec_validate_record error contract parse "contract.yaml not valid YAML or has no status field"
    return
  fi
  # A pristine draft (no criteria yet) is just the starting template
  # placeholder — nothing compiled yet, so the freeze schema does not apply.
  # Only validate once the contract has been populated.
  local nc
  nc="$(yq e '.criteria | length' "$cf" 2>/dev/null || echo 0)"
  if [ "${nc:-0}" -eq 0 ]; then
    return
  fi
  goalspec_validate_run_check error contract schema goalspec_schema_contract_freeze
}

goalspec_validate_evidence() {
  local ef="$GOALSPEC_ROOT/active/evidence.yaml"
  [ -f "$ef" ] || return  # evidence is optional until execution begins
  if ! yq e '.evidence' "$ef" >/dev/null 2>&1; then
    goalspec_validate_record error evidence parse "evidence.yaml invalid (no .evidence key)"
    return
  fi
  local cf="$GOALSPEC_ROOT/active/contract.yaml" cur_chash=""
  [ -f "$cf" ] && cur_chash="$(goalspec_contract_hash)"
  local n i eid ch
  n="$(yq e '.evidence | length' "$ef" 2>/dev/null || echo 0)"
  i=0
  while [ "$i" -lt "$n" ]; do
    eid="$(yq e ".evidence[$i].id // \"\"" "$ef")"
    ch="$(yq e ".evidence[$i].contract_hash // \"\"" "$ef")"
    if [ -n "$cur_chash" ] && [ -n "$ch" ] && [ "$ch" != "null" ] && [ "$ch" != "$cur_chash" ]; then
      goalspec_validate_record warning evidence contract_hash "evidence ${eid}: contract_hash does not match current contract (evidence is stale)"
    fi
    i=$((i+1))
  done
}

goalspec_validate_verdict() {
  local vf="$GOALSPEC_ROOT/active/verdict.yaml"
  [ -f "$vf" ] || return
  if ! yq e '.verdicts' "$vf" >/dev/null 2>&1; then
    goalspec_validate_record error verdict parse "verdict.yaml invalid (no .verdicts key)"
    return
  fi
  local n i
  n="$(yq e '.verdicts | length' "$vf" 2>/dev/null || echo 0)"
  i=0
  while [ "$i" -lt "$n" ]; do
    local missing="" f v vval eby
    for f in criteria_ref verdict context reason evaluated_by; do
      v="$(yq e ".verdicts[$i].${f} // \"\"" "$vf")"
      { [ -z "$v" ] || [ "$v" = "null" ]; } && missing="${missing}${f} "
    done
    [ -z "$missing" ] || goalspec_validate_record error verdict schema "verdict[$i] missing fields: $missing"
    vval="$(yq e ".verdicts[$i].verdict // \"\"" "$vf")"
    case "$vval" in
      pass|fail|insufficient|blocked|stale|reopen_required|"") ;;
      *) goalspec_validate_record error verdict schema "verdict[$i] invalid verdict value: $vval" ;;
    esac
    # evaluated_by must be master (enhance.md §12: Subagent cannot author a
    # final verdict). Guardian was removed, so master is the only valid author.
    eby="$(yq e ".verdicts[$i].evaluated_by // \"\"" "$vf")"
    { [ -n "$eby" ] && [ "$eby" != "null" ] && [ "$eby" != "master" ]; } && \
      goalspec_validate_record error verdict schema "verdict[$i] evaluated_by must be 'master' (got '$eby'); Subagent cannot produce a final verdict"
    i=$((i+1))
  done
}

goalspec_validate_state() {
  local sf="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$sf" ] || { goalspec_validate_record error state presence "state.yaml not found"; return; }
  local st; st="$(yq e '.status // ""' "$sf")"
  [ -n "$st" ] || goalspec_validate_record error state schema "state.yaml missing .status"
  # Staleness is informational lifecycle state, not corruption -> warnings.
  goalspec_stale_goal_changed                   && goalspec_validate_record warning state stale "goal.md changed since approval (re-approve goal)"
  goalspec_stale_contract_changed               && goalspec_validate_record warning state stale "contract.yaml changed since freeze (re-freeze)"
  goalspec_stale_memory_patch_changed           && goalspec_validate_record warning state stale "memory-patch.yaml changed since approval (re-approve memory-patch)"
  goalspec_stale_intake_capture_changed         && goalspec_validate_record warning state stale "intake-capture.md changed since approval"
  goalspec_stale_intake_package_changed         && goalspec_validate_record warning state stale "intake package changed since approval"
  goalspec_stale_constraint_suggestions_applied && goalspec_validate_record warning state stale "constraint-suggestions changed since apply"
}

goalspec_validate_intake() {
  local cs="$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
  [ -f "$cs" ] || return  # intake artifacts are optional
  if ! yq e '.project_constraints' "$cs" >/dev/null 2>&1; then
    goalspec_validate_record error intake parse "constraint-suggestions.yaml invalid"
  fi
}

# --- cross-file reference integrity (--strict) -------------------------------
# Verifies that every id referenced across contract/verdict/evidence points at a
# record that actually exists. This is the capability no gate command checks today.
goalspec_validate_integrity() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  local vf="$GOALSPEC_ROOT/active/verdict.yaml"
  [ -f "$cf" ] || return

  local crit_ids evidreq_ids
  crit_ids="$(yq e '.criteria[].id' "$cf" 2>/dev/null)"
  evidreq_ids="$(yq e '.evidence_requirements[].id' "$cf" 2>/dev/null)"

  local n i id r
  # criteria: evidence_requirement_refs resolve
  n="$(yq e '.criteria | length' "$cf" 2>/dev/null || echo 0)"; i=0
  while [ "$i" -lt "$n" ]; do
    id="$(yq e ".criteria[$i].id" "$cf")"
    for r in $(yq e ".criteria[$i].evidence_requirement_refs[]" "$cf" 2>/dev/null); do
      goalspec_validate_in_list "$r" "$evidreq_ids" || \
        goalspec_validate_record error contract integrity "criteria ${id}: evidence_requirement_ref '$r' not found in evidence_requirements"
    done
    i=$((i+1))
  done

  # verdicts: criteria_ref / evidence_refs resolve
  if [ -f "$vf" ]; then
    n="$(yq e '.verdicts | length' "$vf" 2>/dev/null || echo 0)"; i=0
    while [ "$i" -lt "$n" ]; do
      local cr
      cr="$(yq e ".verdicts[$i].criteria_ref // \"\"" "$vf")"
      goalspec_validate_in_list "$cr" "$crit_ids" || \
        goalspec_validate_record error verdict integrity "verdict[$i] criteria_ref '$cr' not found in criteria"
      for r in $(yq e ".verdicts[$i].evidence_refs[]" "$vf" 2>/dev/null); do
        goalspec_schema_evidence_id "$r" || \
          goalspec_validate_record error verdict integrity "verdict[$i] evidence_ref '$r' not found in evidence.yaml"
      done
      i=$((i+1))
    done
  fi

  # orphan evidence_requirements (warning): defined but referenced by nothing
  if [ -n "$evidreq_ids" ]; then
    local referenced er
    referenced="$(yq e '[.criteria[].evidence_requirement_refs[]]' "$cf" 2>/dev/null | yq e '.[]' - 2>/dev/null)"
    for er in $evidreq_ids; do
      goalspec_validate_in_list "$er" "$referenced" || \
        goalspec_validate_record warning contract integrity "evidence_requirement '$er' not referenced by any criteria"
    done
  fi
}

# --- close-readiness preview (warnings, only meaningful mid-execution) --
# Mirrors the close completion gate as informational warnings so you can see
# what still blocks `run`/`complete`/`close` without attempting them. Runs only
# once execution has begun (contract frozen + at least one verdict recorded) to
# avoid noise. V2: memory-patch approval is no longer a separate gate — the
# close package hash binds the memory_patch_hash, so close is the confirmation.
goalspec_validate_completion_preview() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  local vf="$GOALSPEC_ROOT/active/verdict.yaml"
  local sf="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$cf" ] || return
  [ "$(yq e '.status // ""' "$cf")" = "frozen" ] || return
  [ -f "$vf" ] || return
  [ -f "$sf" ] || return

  local cur rec
  cur="$(goalspec_contract_hash)"
  rec="$(yq e '.contract_hash // ""' "$sf")"
  if [ -n "$rec" ] && [ "$rec" != "null" ] && [ "$cur" != "$rec" ]; then
    goalspec_validate_record warning completion contract_hash "contract changed since freeze; close will require re-freeze"
  fi
  local cur_scope rec_scope scope_err
  cur_scope="$(goalspec_scope_hash)"
  rec_scope="$(yq e '.scope_hash // ""' "$sf")"
  if [ -n "$rec_scope" ] && [ "$rec_scope" != "null" ] && [ "$cur_scope" != "$rec_scope" ]; then
    goalspec_validate_record warning completion scope_hash "effective scope changed since last approval; run goalspec scope amend with a reason"
  fi
  if ! scope_err="$(GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run 2>&1 >/dev/null)"; then
    goalspec_validate_record warning completion scope_check "$scope_err; if these files still serve the current Goal without changing Criteria, run goalspec scope-check --suggest"
  fi

  local qf="$GOALSPEC_ROOT/active/questions.yaml"
  if [ -f "$qf" ]; then
    local nb; nb="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$qf" 2>/dev/null || echo 0)"
    [ "${nb:-0}" -eq 0 ] || goalspec_validate_record warning completion blocking_questions "${nb} blocking question(s) unresolved; close will fail"
  fi

  local crit_ids c blocker missing="" bad=""
  crit_ids="$(yq e '.criteria[].id' "$cf" 2>/dev/null)"
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    if ! blocker="$(goalspec_close_criterion_pass_blocker "$c")"; then
      case "$blocker" in
        no_pass) missing="${missing}${c} " ;;
        *) bad="${bad}${c}:${blocker} " ;;
      esac
    fi
  done <<<"$crit_ids"
  [ -z "$missing" ] || goalspec_validate_record warning completion verdicts "no fresh pass verdict for required/final/hard: $missing"
  [ -z "$bad" ] || goalspec_validate_record warning completion verdicts "stale or non-pass verdict on required/final/hard: $bad"

  local mpf="$GOALSPEC_ROOT/active/memory-patch.yaml"
  if [ ! -f "$mpf" ]; then
    goalspec_validate_record warning completion memory_patch "memory-patch.yaml missing; close will fail (Master proposes, close confirms)"
  fi
}

# --- driver + output ---------------------------------------------------------

goalspec_validate_run() {
  local target="$1" strict="$2"
  GOALSPEC_VALIDATE_STRICT="$strict"
  GOALSPEC_VALIDATE_FINDINGS=()
  case "$target" in
    goal|contract|evidence|verdict|state|intake) "goalspec_validate_${target}" ;;
    all)
      goalspec_validate_goal
      goalspec_validate_contract
      goalspec_validate_evidence
      goalspec_validate_verdict
      goalspec_validate_state
      goalspec_validate_intake
      ;;
    *) goalspec_die "validate: unknown target '$target' (goal|contract|evidence|verdict|state|intake|all)" ;;
  esac
  # Cross-file integrity is meaningful only with the contract present.
  if [ "$strict" = "1" ] && { [ "$target" = "all" ] || [ "$target" = "contract" ]; } \
     && [ -f "$GOALSPEC_ROOT/active/contract.yaml" ]; then
    goalspec_validate_integrity
  fi
  if [ "$target" = "all" ]; then
    goalspec_validate_completion_preview
  fi
}

# Escape a string for a YAML double-quoted scalar (used to feed yq -o=json).
goalspec_validate_yaml_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

goalspec_validate_emit() {
  local json="$1"
  local n_err=0 n_warn=0 cnt
  cnt="${#GOALSPEC_VALIDATE_FINDINGS[@]}"
  if [ "$cnt" -gt 0 ]; then
    local entry sev
    for entry in "${GOALSPEC_VALIDATE_FINDINGS[@]}"; do
      sev="${entry%%$'\t'*}"
      case "$sev" in
        error) n_err=$((n_err+1)) ;;
        warning) n_warn=$((n_warn+1)) ;;
      esac
    done
  fi

  if [ "$json" = "1" ]; then
    {
      printf 'ok: %s\n' "$([ "$n_err" -eq 0 ] && echo true || echo false)"
      printf 'errors: %s\n' "$n_err"
      printf 'warnings: %s\n' "$n_warn"
      if [ "$cnt" -eq 0 ]; then
        printf 'findings: []\n'
      else
        printf 'findings:\n'
        local entry sev rest target check msg
        for entry in "${GOALSPEC_VALIDATE_FINDINGS[@]}"; do
          sev="${entry%%$'\t'*}"; rest="${entry#*$'\t'}"
          target="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
          check="${rest%%$'\t'*}"; msg="${rest#*$'\t'}"
          printf -- '- severity: %s\n  target: %s\n  check: %s\n  message: "%s"\n' \
            "$sev" "$target" "$check" "$(goalspec_validate_yaml_escape "$msg")"
        done
      fi
    } | yq -o=json -I=0 '.'
    return 0
  fi

  if [ "$cnt" -eq 0 ]; then
    echo "validate: ok (no findings)"
  else
    local entry sev rest target check msg tag
    for entry in "${GOALSPEC_VALIDATE_FINDINGS[@]}"; do
      sev="${entry%%$'\t'*}"; rest="${entry#*$'\t'}"
      target="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
      check="${rest%%$'\t'*}"; msg="${rest#*$'\t'}"
      tag="WARN"; [ "$sev" = "error" ] && tag="ERROR"
      printf '[%s] %s %s: %s\n' "$tag" "$target" "$check" "$msg"
    done
  fi
  printf 'validate: %d error(s), %d warning(s)\n' "$n_err" "$n_warn"
}

# Returns 0 (clean / warnings-only) or 1 (any error, or any warning under strict).
goalspec_validate_exit_code() {
  local strict="$1"
  [ "${#GOALSPEC_VALIDATE_FINDINGS[@]}" -gt 0 ] || return 0
  local entry sev
  for entry in "${GOALSPEC_VALIDATE_FINDINGS[@]}"; do
    sev="${entry%%$'\t'*}"
    [ "$sev" = "error" ] && return 1
    [ "$strict" = "1" ] && [ "$sev" = "warning" ] && return 1
  done
  return 0
}
