#!/usr/bin/env bash
# git_delivery.sh — git, safety, and PR delivery helpers for goalspec close.

goalspec_git_default_branch() {
  local b
  b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [ -n "$b" ] || b="$(git branch --format='%(refname:short)' | grep -E '^(main|master)$' | head -1 || true)"
  [ -n "$b" ] || echo "main" || true
  [ -z "$b" ] || echo "$b"
}

goalspec_git_current_branch() {
  git branch --show-current 2>/dev/null || true
}

goalspec_git_remote() {
  git remote | head -1
}

goalspec_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48
}

goalspec_delivery_branch_name() {
  local goal_id="$1" summary="$2" slug
  slug="$(goalspec_slugify "$summary")"
  [ -n "$slug" ] || slug="change"
  printf 'goalspec/%s-%s\n' "$(goalspec_slugify "$goal_id")" "$slug"
}

goalspec_delivery_ensure_branch() {
  local state_file="$GOALSPEC_ROOT/active/state.yaml"
  local goal_id summary cur branch base
  branch="$(yq e '.close.branch // ""' "$state_file")"
  if [ -n "$branch" ] && [ "$branch" != "null" ]; then
    git checkout "$branch" >/dev/null 2>&1 || return 1
    echo "$branch"
    return 0
  fi
  cur="$(goalspec_git_current_branch)"
  base="$(goalspec_git_default_branch)"
  [ -n "$cur" ] || return 1
  if [ "$cur" = "main" ] || [ "$cur" = "master" ]; then
    goal_id="$(yq e '.active_goal_id // "goal"' "$state_file")"
    summary="$(yq e '.goal_summary // "change"' "$GOALSPEC_ROOT/active/close-package.yaml")"
    branch="$(goalspec_delivery_branch_name "$goal_id" "$summary")"
    git checkout -B "$branch" >/dev/null 2>&1 || return 1
  else
    branch="$cur"
  fi
  yq e -i ".close.branch = \"$branch\" | .close.base_branch = \"$base\"" "$state_file"
  echo "$branch"
}

goalspec_delivery_stage_files() {
  local base f
  base="$(yq e '.git.base_revision // ""' "$GOALSPEC_ROOT/active/state.yaml")"
  goalspec_git_changed_files "$base" | sort -u | while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      .goalspec/*|AGENTS.md|CLAUDE.md|README.md|runtime/*|skills/*|tests/*|goalspec|goalspec_enhance.md|enhance_v2.md)
        git add -- "$f" ;;
      *)
        git add -- "$f" ;;
    esac
  done
}

goalspec_delivery_has_staged_changes() {
  ! git diff --cached --quiet --exit-code
}

goalspec_delivery_scan_secrets() {
  local files f hits=""
  files="$(git diff --cached --name-only; git diff --name-only; git ls-files --others --exclude-standard)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$PROJECT_ROOT/$f" ] || continue
    case "$f" in
      *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.gz|*.tgz|*.exe) continue ;;
    esac
    if grep -Eiq '(-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|aws_secret_access_key|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{20,}|token[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{24,}|password[[:space:]]*[:=][[:space:]]*[^[:space:]]{12,})' "$PROJECT_ROOT/$f" 2>/dev/null; then
      hits="${hits}${f} "
    fi
    if [ "$(wc -c < "$PROJECT_ROOT/$f")" -gt 5242880 ]; then
      hits="${hits}${f}:large "
    fi
  done <<<"$files"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

goalspec_delivery_run_final_verification() {
  local pf="$GOALSPEC_ROOT/project/profile.yaml"
  local keys key n i cmd status vout
  [ -f "$pf" ] || return 0
  vout="$(mktemp)"
  keys="test build lint typecheck"
  for key in $keys; do
    n="$(yq e ".commands.$key | length" "$pf" 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] || continue
    i=0
    while [ "$i" -lt "$n" ]; do
      cmd="$(yq e ".commands.$key[$i]" "$pf")"
      if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        if ( cd "$PROJECT_ROOT" && bash -lc "$cmd" ) >"$vout" 2>&1; then
          status=0
        else
          status=$?
        fi
        [ "$status" -eq 0 ] || { cat "$vout" >&2; /bin/rm -f "$vout"; return 1; }
      fi
      i=$((i+1))
    done
  done
  /bin/rm -f "$vout"
}

goalspec_delivery_create_pr() {
  local title body base remote branch out
  command -v gh >/dev/null 2>&1 || { echo "gh not found"; return 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh auth status failed"; return 1; }
  title="$(yq e '.pr.title // "Goalspec close"' "$GOALSPEC_ROOT/active/close-package.yaml")"
  body="$(yq e '.pr.body // ""' "$GOALSPEC_ROOT/active/close-package.yaml")"
  base="$(yq e '.close.base_branch // "main"' "$GOALSPEC_ROOT/active/state.yaml")"
  remote="$(yq e '.close.remote // "origin"' "$GOALSPEC_ROOT/active/state.yaml")"
  branch="$(yq e '.close.branch // ""' "$GOALSPEC_ROOT/active/state.yaml")"
  out="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body" 2>&1)" || { echo "$out" >&2; return 1; }
  printf '%s\n' "$out" | tail -1
}
