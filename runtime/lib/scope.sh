#!/usr/bin/env bash
# scope.sh — path matching and scope checks.
# Patterns support glob like 'src/**', 'tests/**' (we translate to find).

# Match a glob-style pattern (supports * and **) against a path.
# Returns 0 if matches. Translation:
#   ** -> matches across directory separators (.*)
#   *  -> matches within a directory segment ([^/]*)
goalspec_path_matches() {
  local pattern="$1" path="$2"
  local i=0 n ch out="^"
  n=${#pattern}
  while [ "$i" -lt "$n" ]; do
    ch="${pattern:$i:1}"
    if [ "$ch" = "*" ]; then
      if [ "${pattern:$((i+1)):1}" = "*" ]; then
        out="${out}.*"; i=$((i+2))
        # consume trailing slash so 'a/**/b' style works naturally
        if [ "${pattern:$i:1}" = "/" ]; then i=$((i+1)); fi
      else
        out="${out}[^/]*"; i=$((i+1))
      fi
    else
      case "$ch" in
        '.'|'\\'|'+'|'^'|'$'|'('|')'|'{'|'}'|'|'|'?') out="${out}\\${ch}" ;;
        *) out="${out}${ch}" ;;
      esac
      i=$((i+1))
    fi
  done
  out="${out}\$"
  [[ "$path" =~ $out ]]
}

# Returns 0 if path is allowed by any pattern in patterns list (newline-separated).
goalspec_path_allowed() {
  local path="$1"; shift
  local p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if goalspec_path_matches "$p" "$path"; then return 0; fi
  done
  return 1
}

# Returns 0 if path matches a forbidden pattern.
goalspec_path_forbidden() {
  local path="$1"; shift
  local p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if goalspec_path_matches "$p" "$path"; then return 0; fi
  done
  return 1
}

# scope-check command body. Returns 0 if all good; prints blockers.
goalspec_scope_check_run() {
  local base files errs=0
  base="$(goalspec_state_get 'git.base_revision')"
  files="$(goalspec_git_changed_files "$base")"
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo "no contract.yaml" >&2; return 1; }
  local contract_status
  contract_status="$(yq e '.status' "$cf")"

  # Build WU id -> allowed/forbidden tables.
  local n_wu idx wu_id
  n_wu="$(yq e '.work_units | length' "$cf")"
  declare -A WU_ALLOWED
  declare -A WU_FORBIDDEN
  declare -A WU_PASSED
  idx=0
  while [ "$idx" -lt "$n_wu" ]; do
    wu_id="$(yq e ".work_units[$idx].id" "$cf")"
    WU_ALLOWED[$wu_id]="$(yq e -o=t ".work_units[$idx].allowed_paths.[]" "$cf" | tr '\n' '|')"
    WU_FORBIDDEN[$wu_id]="$(yq e -o=t ".work_units[$idx].forbidden_paths.[]" "$cf" | tr '\n' '|')"
    idx=$((idx+1))
  done

  # Determine passed WUs from verdicts.
  local vf="$GOALSPEC_ROOT/active/verdict.yaml"
  if [ -f "$vf" ]; then
    local n vidx wu v
    n="$(yq e '.verdicts | length' "$vf" 2>/dev/null || echo 0)"
    vidx=0
    while [ "$vidx" -lt "$n" ]; do
      wu="$(yq e ".verdicts[$vidx].work_unit_ref" "$vf")"
      v="$(yq e ".verdicts[$vidx].verdict" "$vf")"
      if [ "$v" = "pass" ]; then
        WU_PASSED[$wu]=1
      fi
      vidx=$((vidx+1))
    done
  fi

  # For each changed business file: must match a passed WU's allowed_paths and
  # not match any forbidden_paths from any WU.
  local unattributed=""
  local forbidden_hits=""
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # global forbidden check (frozen contract / verdict / project / history)
    # MUST be checked BEFORE the generic .goalspec/* skip so executor tampering
    # with these authority files is caught (GOALC #10, §20, §26.6).
    if [ "$contract_status" = "frozen" ]; then
      case "$f" in
        .goalspec/active/contract.yaml|\
        .goalspec/active/verdict.yaml|\
        .goalspec/project/*|\
        .goalspec/history/*)
          forbidden_hits="${forbidden_hits}$f "
          continue
          ;;
      esac
    fi
    case "$f" in
      .goalspec/*) continue ;;
    esac
    # forbidden by any WU forbidden_paths
    local wuu hit_forbidden=0
    for wuu in "${!WU_FORBIDDEN[@]}"; do
      local fp="${WU_FORBIDDEN[$wuu]}"
      local oldifs="$IFS"
      IFS='|'
      # shellcheck disable=SC2086
      set -- $fp
      IFS="$oldifs"
      local pat
      for pat in "$@"; do
        [ -z "$pat" ] && continue
        if goalspec_path_matches "$pat" "$f"; then
          hit_forbidden=1; break
        fi
      done
      [ "$hit_forbidden" = "1" ] && break
    done
    if [ "$hit_forbidden" = "1" ]; then
      forbidden_hits="${forbidden_hits}$f "
      continue
    fi
    # allowed by some passed WU?
    local attributed=0
    local pwu
    for pwu in "${!WU_PASSED[@]}"; do
      local ap="${WU_ALLOWED[$pwu]}"
      local oldifs="$IFS"
      IFS='|'
      # shellcheck disable=SC2086
      set -- $ap
      IFS="$oldifs"
      local pat
      for pat in "$@"; do
        [ -z "$pat" ] && continue
        if goalspec_path_matches "$pat" "$f"; then
          attributed=1; break
        fi
      done
      [ "$attributed" = "1" ] && break
    done
    if [ "$attributed" != "1" ]; then
      unattributed="${unattributed}$f "
    fi
  done <<<"$files"

  if [ -n "$forbidden_hits" ]; then
    echo "scope-check: forbidden paths modified: $forbidden_hits" >&2
    errs=$((errs+1))
  fi
  if [ -n "$unattributed" ]; then
    echo "scope-check: business files not attributed to a passed WU: $unattributed" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ]
}
