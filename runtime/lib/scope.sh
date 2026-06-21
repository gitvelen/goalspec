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
# Goal-driven model (enhance.md §7/§13): scope is the Constraints boundary.
# A changed business file must match a contract-level allowed_paths pattern
# and must not match any contract-level forbidden_paths pattern. There are no
# per-work-unit scopes.
goalspec_scope_check_run() {
  local base files errs=0
  base="$(goalspec_state_get 'git.base_revision')"
  files="$(goalspec_git_changed_files "$base")"
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo "no contract.yaml" >&2; return 1; }
  local contract_status
  contract_status="$(yq e '.status' "$cf" 2>/dev/null)"
  if [ -z "$contract_status" ] || [ "$contract_status" = "null" ]; then
    echo "scope-check: contract.yaml cannot be parsed or has no status" >&2
    return 1
  fi

  # Contract-level allowed / forbidden path tables (the Constraints boundary).
  local ALLOWED FORBIDDEN
  ALLOWED="$(yq e -o=t '.allowed_paths[]' "$cf" 2>/dev/null)"
  FORBIDDEN="$(yq e -o=t '.forbidden_paths[]' "$cf" 2>/dev/null)"

  # Role context: GOALSPEC_SCOPE_ROLE=subagent (default) checks the strict
  # Subagent view (no touching verdict/memory-patch/etc.). =system (used by
  # `complete` after the Master writes) relaxes those active-write checks
  # because their integrity is enforced by hash/context in judge apply / approve.
  local role="${GOALSPEC_SCOPE_ROLE:-subagent}"
  local unattributed=""
  local forbidden_hits=""
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Frozen contract authority file. freeze writes contract_hash into
    # contract.yaml itself, which makes the file permanently "dirty" relative to
    # base_revision. Distinguish that benign self-write from a real edit by
    # comparing the current content hash to the hash recorded at freeze time.
    if [ "$contract_status" = "frozen" ]; then
      case "$f" in
        .goalspec/active/contract.yaml)
          local rec_chash
          rec_chash="$(goalspec_state_get 'contract_hash')"
          if [ -n "$rec_chash" ] && [ "$rec_chash" != "null" ] && [ "$rec_chash" = "$(goalspec_contract_hash)" ]; then
            : # contract content matches frozen snapshot; not a tampering event
          else
            forbidden_hits="${forbidden_hits}$f "
          fi
          continue
          ;;
      esac
    fi
    # Subagent-only forbidden authority files. The executor (Subagent) must never
    # directly write the Master/approval files, the long-term project memory, or
    # the history archive. The close flow (role=system) legitimately stages
    # .goalspec/project/** and .goalspec/history/** per V2 §12 (approved memory
    # patch + history archive), so those are exempt for the system role.
    if [ "$role" = "subagent" ] && [ "$contract_status" = "frozen" ]; then
      case "$f" in
        .goalspec/active/verdict.yaml|\
        .goalspec/active/memory-patch.yaml|\
        .goalspec/active/reviews.yaml|\
        .goalspec/active/regressions.yaml|\
        .goalspec/active/harness-improvement-candidate.yaml|\
        .goalspec/project/*|\
        .goalspec/history/*)
          forbidden_hits="${forbidden_hits}$f "
          continue
          ;;
      esac
    fi
    if goalspec_git_is_framework_file "$f"; then continue; fi
    # forbidden by any contract forbidden_paths
    local pat hit_forbidden=0
    local oldifs="$IFS"
    IFS=$'\n'
    for pat in $FORBIDDEN; do
      [ -z "$pat" ] && continue
      if goalspec_path_matches "$pat" "$f"; then
        hit_forbidden=1; break
      fi
    done
    IFS="$oldifs"
    if [ "$hit_forbidden" = "1" ]; then
      forbidden_hits="${forbidden_hits}$f "
      continue
    fi
    # allowed by some contract allowed_paths?
    local attributed=0
    oldifs="$IFS"
    IFS=$'\n'
    for pat in $ALLOWED; do
      [ -z "$pat" ] && continue
      if goalspec_path_matches "$pat" "$f"; then
        attributed=1; break
      fi
    done
    IFS="$oldifs"
    if [ "$attributed" != "1" ]; then
      unattributed="${unattributed}$f "
    fi
  done <<<"$files"

  if [ -n "$forbidden_hits" ]; then
    echo "scope-check: forbidden paths modified: $forbidden_hits" >&2
    errs=$((errs+1))
  fi
  if [ -n "$unattributed" ]; then
    echo "scope-check: business files not within contract allowed_paths: $unattributed" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ]
}
