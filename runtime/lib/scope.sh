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

goalspec_scope_amendments_file() {
  printf '%s\n' "$GOALSPEC_ROOT/active/scope-amendments.yaml"
}

goalspec_scope_ensure_amendments_file() {
  local af
  af="$(goalspec_scope_amendments_file)"
  [ -f "$af" ] || cp "$GOALSPEC_ROOT/runtime/templates/active/scope-amendments.yaml" "$af"
}

goalspec_scope_allowed_patterns() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml" af
  [ -f "$cf" ] && yq e -o=t '.allowed_paths[]' "$cf" 2>/dev/null || true
  af="$(goalspec_scope_amendments_file)"
  [ -f "$af" ] && yq e -o=t '.amendments[] | select(.status == "approved") | .allowed_paths[]' "$af" 2>/dev/null || true
}

goalspec_scope_forbidden_patterns() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] && yq e -o=t '.forbidden_paths[]' "$cf" 2>/dev/null || true
}

goalspec_scope_suggest_patterns() {
  local files="$1" f pat out=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      */*) pat="${f%%/*}/**" ;;
      *) pat="$f" ;;
    esac
    case "$out" in
      *"$pat"$'\n'*|*"$pat") ;;
      *) out="${out}${pat}"$'\n' ;;
    esac
  done <<<"$files"
  printf '%s' "$out" | sed '/^$/d' | sort -u
}

goalspec_scope_print_suggestions() {
  [ -n "$GOALSPEC_SCOPE_LAST_UNATTRIBUTED" ] || return 0
  echo "suggested allowed_paths:" >&2
  goalspec_scope_suggest_patterns "$(printf '%s\n' "$GOALSPEC_SCOPE_LAST_UNATTRIBUTED" | tr ' ' '\n')" | sed 's/^/  - /' >&2
  echo "next: if these files still serve the current Goal without changing Goal, Criteria, or semantic Constraints, run: goalspec scope amend --allow <glob> --reason <why>" >&2
  echo "reopen only if the new paths change the Goal, Criteria, or semantic Constraints." >&2
}

goalspec_scope_pattern_hits_forbidden_changed_file() {
  local allow="$1" forbidden="$2" base files f pat
  base="$(goalspec_state_get 'git.base_revision')"
  files="$(goalspec_git_changed_files "$base")"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    goalspec_path_matches "$allow" "$f" || continue
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      if goalspec_path_matches "$pat" "$f"; then
        printf '%s\n' "$f"
        return 0
      fi
    done <<<"$forbidden"
  done <<<"$files"
  return 1
}

goalspec_scope_amend_allow() {
  local reason="$1"; shift
  local af state_file now id old_hash new_hash forbidden allow hit tmp
  [ -n "$reason" ] || { echo "scope amend: --reason is required" >&2; return 2; }
  [ "$#" -gt 0 ] || { echo "scope amend: at least one --allow glob is required" >&2; return 2; }
  goalspec_scope_ensure_amendments_file
  af="$(goalspec_scope_amendments_file)"
  state_file="$GOALSPEC_ROOT/active/state.yaml"
  forbidden="$(goalspec_scope_forbidden_patterns)"
  for allow in "$@"; do
    [ -n "$allow" ] || continue
    if hit="$(goalspec_scope_pattern_hits_forbidden_changed_file "$allow" "$forbidden")"; then
      echo "scope amend: --allow '$allow' would authorize forbidden changed file: $hit" >&2
      return 1
    fi
  done
  old_hash="$(goalspec_scope_hash)"
  now="$(goalspec_now)"
  id="SCOPE-AMEND-$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  {
    printf 'id: "%s"\n' "$id"
    printf 'status: approved\n'
    printf 'approved_at: "%s"\n' "$now"
    printf 'reason: |-\n'
    printf '%s\n' "$reason" | sed 's/^/  /'
    printf 'old_scope_hash: "%s"\n' "$old_hash"
    printf 'new_scope_hash: null\n'
    printf 'allowed_paths:\n'
    for allow in "$@"; do
      [ -n "$allow" ] && printf '  - "%s"\n' "$allow"
    done
  } > "$tmp"
  yq e -i ".amendments += [load(\"$tmp\")]" "$af"
  /bin/rm -f "$tmp"
  new_hash="$(goalspec_scope_hash)"
  local amend_idx
  amend_idx="$(yq e '.amendments | length' "$af")"
  amend_idx=$((amend_idx-1))
  yq e -i "(.amendments[$amend_idx].new_scope_hash = \"$new_hash\")" "$af"
  yq e -i ".scope_hash = \"$new_hash\"" "$state_file"
  if [ -f "$GOALSPEC_ROOT/active/goal-driven-prompt.md" ]; then
    goalspec_prompt_generate
    new_hash="$(goalspec_scope_hash)"
  fi
  case "$(yq e '.status // "no_goal"' "$state_file")" in
    ready_to_close|closing)
      yq e -i '.status = "running" | .close.status = "not_started" | .close.failed_at = null | .close.failure_reason = null | .close_package_hash = null' "$state_file"
      ;;
  esac
  echo "constraints projection amendment approved: $id"
  echo "scope_hash: $new_hash"
  echo "next: run /goalspec run to regenerate the close package if one existed"
}

goalspec_scope_ensure_state_hash() {
  local state_file="$GOALSPEC_ROOT/active/state.yaml" rec cur
  [ -f "$state_file" ] || return 1
  cur="$(goalspec_scope_hash)"
  rec="$(yq e '.scope_hash // ""' "$state_file" 2>/dev/null || echo "")"
  if [ -z "$rec" ] || [ "$rec" = "null" ]; then
    yq e -i ".scope_hash = \"$cur\"" "$state_file"
    if [ -f "$GOALSPEC_ROOT/active/goal-driven-prompt.md" ]; then
      goalspec_prompt_generate
    fi
    return 0
  fi
  [ "$rec" = "$cur" ]
}

GOALSPEC_SCOPE_LAST_UNATTRIBUTED=""
GOALSPEC_SCOPE_LAST_FORBIDDEN=""

# scope-check command body. Returns 0 if all good; prints blockers.
# Goal-driven model (enhance.md §7/§13): scope is the Constraints boundary.
# A changed business file must match a contract-level allowed_paths pattern
# and must not match any contract-level forbidden_paths pattern. There are no
# per-work-unit scopes.
goalspec_scope_check_run() {
  local base files errs=0
  GOALSPEC_SCOPE_LAST_UNATTRIBUTED=""
  GOALSPEC_SCOPE_LAST_FORBIDDEN=""
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
  ALLOWED="$(goalspec_scope_allowed_patterns)"
  FORBIDDEN="$(goalspec_scope_forbidden_patterns)"

  # Role context: GOALSPEC_SCOPE_ROLE=subagent (default) checks the strict
  # Subagent view (no touching verdict/memory-patch/etc.). =system (used by
  # `complete` after the Master writes) relaxes those active-write checks
  # because their integrity is enforced by hash/context in judge apply / approve.
  local role="${GOALSPEC_SCOPE_ROLE:-subagent}"
  local unattributed=""
  local forbidden_hits=""
  local f

  # Authority integrity check (git-independent). When .goalspec/ is gitignored,
  # `git diff`/`ls-files --others` cannot see edits to active/ authority files,
  # so the per-file git-diff branch below never fires for them. The frozen
  # baseline hashes recorded in state.yaml at freeze time are the only tamper
  # signal left. Any drift means a frozen authority file was edited outside the
  # sanctioned freeze/reopen flow — treat it as a forbidden modification.
  if [ "$contract_status" = "frozen" ]; then
    local sf="$GOALSPEC_ROOT/active/state.yaml" field rec cur
    for field in contract_hash criteria_hash constraints_hash goal_hash; do
      rec="$(yq e ".$field // \"\"" "$sf" 2>/dev/null || echo "")"
      [ -n "$rec" ] && [ "$rec" != "null" ] || continue
      case "$field" in
        contract_hash)    cur="$(goalspec_contract_hash)" ;;
        criteria_hash)    cur="$(goalspec_criteria_hash)" ;;
        constraints_hash) cur="$(goalspec_constraints_hash)" ;;
        goal_hash)        cur="$(goalspec_goal_hash)" ;;
      esac
      if [ "$rec" != "$cur" ]; then
        forbidden_hits="${forbidden_hits}frozen_${field}_drift "
      fi
    done
  fi
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
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      if goalspec_path_matches "$pat" "$f"; then
        hit_forbidden=1; break
      fi
    done <<<"$FORBIDDEN"
    if [ "$hit_forbidden" = "1" ]; then
      forbidden_hits="${forbidden_hits}$f "
      continue
    fi
    # allowed by some contract allowed_paths?
    local attributed=0
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      if goalspec_path_matches "$pat" "$f"; then
        attributed=1; break
      fi
    done <<<"$ALLOWED"
    if [ "$attributed" != "1" ]; then
      unattributed="${unattributed}$f "
    fi
  done <<<"$files"

  if [ -n "$forbidden_hits" ]; then
    GOALSPEC_SCOPE_LAST_FORBIDDEN="$forbidden_hits"
    echo "scope-check: forbidden paths modified: $forbidden_hits" >&2
    errs=$((errs+1))
  fi
  if [ -n "$unattributed" ]; then
    GOALSPEC_SCOPE_LAST_UNATTRIBUTED="$unattributed"
    echo "scope-check: business files not within effective allowed_paths: $unattributed" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ]
}
