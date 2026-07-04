#!/usr/bin/env bash
# schema.sh — required-field checks via yq.
# Each function returns 0 if valid, 1 otherwise; prints errors to stderr.

goalspec_schema_require_fields() {
  local file="$1"; shift
  local errs=0
  local field
  for field in "$@"; do
    local v
    v="$(yq e ".${field} // \"\"" "$file" 2>/dev/null)"
    if [ -z "$v" ] || [ "$v" = "null" ]; then
      echo "missing required field: $field" >&2
      errs=$((errs+1))
    fi
  done
  [ "$errs" -eq 0 ]
}

# Validate goal.md has the nine sections. 0 if all present.
goalspec_schema_goal_md() {
  local gf="$GOALSPEC_ROOT/active/goal.md"
  [ -f "$gf" ] || { echo "goal.md not found" >&2; return 1; }
  local errs=0
  for h in "Intent" "Narrative" "Success Model" "Scope" "Risk Scan"; do
    if ! grep -q "## .*${h}" "$gf"; then
      echo "goal.md missing section: $h" >&2
      errs=$((errs+1))
    fi
  done
  [ "$errs" -eq 0 ]
}

# Validate contract.yaml minimal structure for freeze (goal-driven: only
# Goal/Criteria/Constraints; no work_units/coverage_map). Returns 0 if valid.
goalspec_schema_contract_freeze() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  local errs=0
  local n_crit
  n_crit="$(yq e '.criteria | length' "$cf" 2>/dev/null || echo 0)"
  [ "$n_crit" -gt 0 ] 2>/dev/null || { echo "contract: no criteria" >&2; errs=$((errs+1)); }
  # evidence_requirement ids for ref resolution.
  local evidreq_ids
  evidreq_ids="$(yq e '.evidence_requirements[].id' "$cf" 2>/dev/null)"
  # criteria must be declarable: have a statement that is neither vague nor an
  # implementation step, and be decidable from evidence (non-empty, resolving
  # evidence_requirement_refs) — enhance.md §6 Clear/Decidable/Relevant/Minimal.
  local idx=0
  local count="${n_crit}"
  while [ "$idx" -lt "$count" ]; do
    local id stmt erefs
    id="$(yq e ".criteria[$idx].id" "$cf")"
    stmt="$(yq e ".criteria[$idx].statement // \"\"" "$cf")"
    if [ -z "$stmt" ]; then
      echo "criteria ${id}: missing statement" >&2
      errs=$((errs+1))
    fi
    # CJK vague terms have no reliable ERE word boundary in Chinese text, so
    # they are matched as substrings (unchanged coverage). English terms are
    # anchored on ASCII non-letter boundaries so 'incorrect', 'property',
    # 'completeness' do not trip 'correct'/'proper'/'complete'. (-i case-folds
    # the bracket expression too, so [^a-z] effectively matches "non-letter".)
    if printf '%s' "$stmt" | grep -Eiq '(合理|良好|优化|正确|完整|充分支持)|(^|[^a-z])(reasonable|good|optimized|correct|complete|proper|properly)([^a-z]|$)'; then
      echo "criteria ${id}: vague statement must be rewritten before freeze" >&2
      errs=$((errs+1))
    fi
    if printf '%s' "$stmt" | grep -Eiq '(^|[[:space:]])(implement|refactor|use|create file|edit file|修改|实现|重构|使用)([[:space:]]|$)'; then
      echo "criteria ${id}: statement appears to encode implementation steps" >&2
      errs=$((errs+1))
    fi
    # kind: a criterion's verifiability class. Optional — defaults to machine.
    #   machine  — auto-loopable; Master judges from machine-checkable evidence.
    #   judgment — needs human/Master resolution; the run-loop will not blindly
    #              retry these. Declare explicitly only when a criterion cannot
    #              be machine-judged; omit for the common machine case.
    local kind
    kind="$(yq e ".criteria[$idx].kind // \"machine\"" "$cf")"
    case "$kind" in
      machine|judgment) ;;
      *) echo "criteria ${id}: invalid kind '$kind' (expected machine|judgment, or omit for machine)" >&2; errs=$((errs+1)) ;;
    esac
    # Decidable: must carry evidence_requirement_refs that resolve to defined
    # evidence_requirements, otherwise the Master cannot judge pass/fail from
    # evidence (and judge apply's pass-check would be trivially satisfied).
    erefs="$(yq e ".criteria[$idx].evidence_requirement_refs[]" "$cf" 2>/dev/null)"
    if [ -z "$erefs" ]; then
      echo "criteria ${id}: missing evidence_requirement_refs (must be decidable from evidence)" >&2
      errs=$((errs+1))
    else
      local r
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if ! printf '%s\n' "$evidreq_ids" | grep -qxF "$r"; then
          echo "criteria ${id}: evidence_requirement_ref '$r' not found in evidence_requirements" >&2
          errs=$((errs+1))
        fi
      done <<<"$erefs"
    fi
    idx=$((idx+1))
  done
  # final criteria present
  if [ "$(yq e '[.criteria[] | select(.final == true)] | length' "$cf")" -lt 1 ]; then
    echo "contract: missing final criteria" >&2
    errs=$((errs+1))
  fi
  if [ "$(yq e '.allowed_paths | length' "$cf" 2>/dev/null || echo 0)" -lt 1 ]; then
    echo "contract: allowed_paths must not be empty; use wide domain globs such as src/** and tests/**" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ]
}

# Validate a verdict file passed to judge apply.
goalspec_schema_verdict_file() {
  local vf="$1"
  [ -f "$vf" ] || { echo "verdict file not found: $vf" >&2; return 1; }
  local errs=0
  for f in "criteria_ref" "verdict" "contract_hash" "evidence_hash" "context" "reason" "evaluated_by"; do
    local v
    v="$(yq e ".${f} // \"\"" "$vf")"
    if [ -z "$v" ]; then
      echo "verdict missing field: $f" >&2
      errs=$((errs+1))
    fi
  done
  # verdict enum
  local vval
  vval="$(yq e '.verdict' "$vf")"
  case "$vval" in
    pass|fail|insufficient|blocked|stale|reopen_required) ;;
    *) echo "verdict has invalid value: $vval" >&2; errs=$((errs+1)) ;;
  esac
  # evaluated_by must be master (enhance.md §12: Subagent cannot produce a
  # final success verdict; only the Master judges). Guardian was removed in
  # the goal-driven refactor, so master is the only valid author.
  local eby
  eby="$(yq e '.evaluated_by // ""' "$vf")"
  if [ -n "$eby" ] && [ "$eby" != "master" ]; then
    echo "verdict evaluated_by must be 'master' (got '$eby'); Subagent cannot produce a final verdict" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ]
}

# Validate an evidence entry by id within evidence.yaml.
goalspec_schema_evidence_id() {
  local ef="$GOALSPEC_ROOT/active/evidence.yaml" id="$1"
  local found
  found="$(yq e ".evidence[] | select(.id == \"$id\") | .id" "$ef")"
  [ -n "$found" ]
}

# Structural validation for the fields sensor verification relies on. An entry
# marked reproducible:true must carry a non-empty command (otherwise the sensor
# re-run at judge apply cannot confirm it). Prints errors to stderr; 0 if valid.
goalspec_schema_evidence_entry() {
  local ef="$GOALSPEC_ROOT/active/evidence.yaml" id="$1"
  local found repro cmd
  found="$(yq e ".evidence[] | select(.id == \"$id\") | .id" "$ef" 2>/dev/null)"
  [ -n "$found" ] || { echo "evidence $id: not found" >&2; return 1; }
  repro="$(yq e ".evidence[] | select(.id == \"$id\") | .reproducible // false" "$ef")"
  if [ "$repro" = "true" ]; then
    cmd="$(yq e ".evidence[] | select(.id == \"$id\") | .command // \"\"" "$ef")"
    if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
      echo "evidence $id: reproducible=true requires a non-empty command" >&2
      return 1
    fi
    # J2: judgment evidence must not silently masquerade as fully
    # sensor-verifiable. The sensor re-runs .command and checks exit 0 — it can
    # confirm an artifact exists, but never that a human visual/qualitative call
    # holds. A manual-observation entry marked reproducible MUST declare
    # sensor_scope to bound what the sensor actually proves, forcing the author
    # to acknowledge the unverifiable judgment portion instead of letting an
    # unrelated 'ls' command lend it an objective aura (velentrade P2-002).
    local cl rb ss
    cl="$(yq e ".evidence[] | select(.id == \"$id\") | .completion_level // \"\"" "$ef")"
    rb="$(yq e ".evidence[] | select(.id == \"$id\") | .runtime_boundary // \"\"" "$ef")"
    if [ "$cl" = "manual_observation" ] || [ "$rb" = "manual" ]; then
      ss="$(yq e ".evidence[] | select(.id == \"$id\") | .sensor_scope // \"\"" "$ef")"
      if [ -z "$ss" ] || [ "$ss" = "null" ]; then
        echo "evidence $id: reproducible=true with manual observation requires a 'sensor_scope' field (e.g. 'artifact_existence_only') to bound what the sensor verifies — the judgment itself is not sensor-verifiable" >&2
        return 1
      fi
    fi
  fi
  return 0
}
