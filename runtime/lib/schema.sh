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

# Validate work_unit entry has required fields.
goalspec_schema_work_unit() {
  local file="$1" id="$2"
  goalspec_schema_require_fields "$file" \
    ".work_units[] | select(.id == \"$id\") | .id" 2>/dev/null || true
}

# Validate contract.yaml minimal structure for freeze.
# Returns 0 if valid; prints errors.
goalspec_schema_contract_freeze() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  local errs=0
  local n_crit n_wu n_cov
  n_crit="$(yq e '.criteria | length' "$cf" 2>/dev/null || echo 0)"
  n_wu="$(yq e '.work_units | length' "$cf" 2>/dev/null || echo 0)"
  n_cov="$(yq e '.coverage_map | length' "$cf" 2>/dev/null || echo 0)"
  [ "$n_crit" -gt 0 ] 2>/dev/null || { echo "contract: no criteria" >&2; errs=$((errs+1)); }
  [ "$n_wu" -gt 0 ] 2>/dev/null || { echo "contract: no work_units" >&2; errs=$((errs+1)); }
  [ "$n_cov" -gt 0 ] 2>/dev/null || { echo "contract: no coverage_map" >&2; errs=$((errs+1)); }
  # criteria must be declarable: have statement + pass_signals OR evidence refs
  local idx=0
  local count="${n_crit}"
  while [ "$idx" -lt "$count" ]; do
    local id stmt
    id="$(yq e ".criteria[$idx].id" "$cf")"
    stmt="$(yq e ".criteria[$idx].statement // \"\"" "$cf")"
    if [ -z "$stmt" ]; then
      echo "criteria ${id}: missing statement" >&2
      errs=$((errs+1))
    fi
    if printf '%s' "$stmt" | grep -Eiq '(合理|良好|优化|正确|完整|充分支持|reasonable|good|optimized|correct|complete|proper|properly)'; then
      echo "criteria ${id}: vague statement must be rewritten before freeze" >&2
      errs=$((errs+1))
    fi
    if printf '%s' "$stmt" | grep -Eiq '(^|[[:space:]])(implement|refactor|use|create file|edit file|修改|实现|重构|使用)([[:space:]]|$)'; then
      echo "criteria ${id}: statement appears to encode implementation steps" >&2
      errs=$((errs+1))
    fi
    idx=$((idx+1))
  done
  # final criteria present
  if [ "$(yq e '[.criteria[] | select(.final == true)] | length' "$cf")" -lt 1 ]; then
    echo "contract: missing final criteria" >&2
    errs=$((errs+1))
  fi
  # every WU has criteria_refs
  idx=0; count="$n_wu"
  while [ "$idx" -lt "$count" ]; do
    local id crefs areal
    id="$(yq e ".work_units[$idx].id" "$cf")"
    crefs="$(yq e ".work_units[$idx].criteria_refs | length" "$cf")"
    if [ "${crefs:-0}" -lt 1 ]; then
      echo "work_unit ${id}: missing criteria_refs" >&2
      errs=$((errs+1))
    fi
    # allowed_paths must not be wildcard-only without approval
    areal="$(yq e ".work_units[$idx].allowed_paths | length" "$cf")"
    if [ "${areal:-0}" -lt 1 ]; then
      echo "work_unit ${id}: missing allowed_paths" >&2
      errs=$((errs+1))
    fi
    idx=$((idx+1))
  done
  [ "$errs" -eq 0 ]
}

# Validate a verdict file passed to judge apply.
goalspec_schema_verdict_file() {
  local vf="$1"
  [ -f "$vf" ] || { echo "verdict file not found: $vf" >&2; return 1; }
  local errs=0
  for f in "work_unit_ref" "criteria_ref" "verdict" "contract_hash" "evidence_hash" "context" "reason"; do
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
  [ "$errs" -eq 0 ]
}

# Validate an evidence entry by id within evidence.yaml.
goalspec_schema_evidence_id() {
  local ef="$GOALSPEC_ROOT/active/evidence.yaml" id="$1"
  local found
  found="$(yq e ".evidence[] | select(.id == \"$id\") | .id" "$ef")"
  [ -n "$found" ]
}
