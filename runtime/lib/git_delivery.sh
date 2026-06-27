#!/usr/bin/env bash
# git_delivery.sh — git, safety, and PR delivery helpers for goalspec close.

goalspec_delivery_profile_value() {
  local expr="$1" default="$2" pf="$GOALSPEC_ROOT/project/profile.yaml" val
  val="$(yq e "$expr // \"\"" "$pf" 2>/dev/null || true)"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "$default"
  else
    echo "$val"
  fi
}

goalspec_delivery_mode() {
  local mode
  mode="$(goalspec_delivery_profile_value '.delivery.mode' 'github_pr')"
  case "$mode" in
    github_pr|push_only|local_commit|archive_only) echo "$mode" ;;
    *) echo "invalid:$mode" ;;
  esac
}

goalspec_git_default_branch() {
  local configured b
  configured="$(goalspec_delivery_profile_value '.delivery.base_branch' '')"
  [ -n "$configured" ] && { echo "$configured"; return 0; }
  b="$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [ -n "$b" ] || b="$(git -C "$PROJECT_ROOT" branch --format='%(refname:short)' | grep -E '^(main|master)$' | head -1 || true)"
  [ -n "$b" ] || echo "main" || true
  [ -z "$b" ] || echo "$b"
}

goalspec_git_current_branch() {
  git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || true
}

goalspec_git_remote_detected() {
  git -C "$PROJECT_ROOT" remote | head -1
}

goalspec_delivery_remote() {
  goalspec_git_remote
}

goalspec_delivery_base_branch() {
  goalspec_git_default_branch
}

goalspec_git_remote() {
  local configured
  configured="$(goalspec_delivery_profile_value '.delivery.remote' '')"
  if [ -n "$configured" ]; then
    git -C "$PROJECT_ROOT" remote get-url "$configured" >/dev/null 2>&1 && echo "$configured"
    return 0
  fi
  goalspec_git_remote_detected
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
    git -C "$PROJECT_ROOT" checkout "$branch" >/dev/null 2>&1 || return 1
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
    git -C "$PROJECT_ROOT" checkout -B "$branch" >/dev/null 2>&1 || return 1
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
    git -C "$PROJECT_ROOT" add -- "$f"
  done
}

goalspec_delivery_has_staged_changes() {
  ! git -C "$PROJECT_ROOT" diff --cached --quiet --exit-code
}

# Is path f covered by the project's scan_allow_paths glob list? Used to exempt
# known false-positive paths (tests/fixtures/docs with dummy credentials).
# args: <path> <newline-separated-patterns>
goalspec_scan_path_allowed() {
  local f="$1" patterns="$2" pat
  [ -n "$patterns" ] || return 1
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$f" in $pat) return 0 ;; esac
  done <<<"$patterns"
  return 1
}

goalspec_delivery_scan_secrets() {
  local files f hits="" allow_patterns
  files="$(git -C "$PROJECT_ROOT" diff --cached --name-only; git -C "$PROJECT_ROOT" diff --name-only; git -C "$PROJECT_ROOT" ls-files --others --exclude-standard)"
  allow_patterns="$(yq e '.delivery.scan_allow_paths // [] | .[]' "$GOALSPEC_ROOT/project/profile.yaml" 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$PROJECT_ROOT/$f" ] || continue
    case "$f" in
      *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.gz|*.tgz|*.exe) continue ;;
    esac
    # Allowlist: skip paths the project declared as known false-positives.
    goalspec_scan_path_allowed "$f" "$allow_patterns" && continue
    # High-signal static patterns (PEM keys, aws/api/token literals) — rarely
    # appear in safe code, matched as-is.
    if grep -Eiq '(-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|aws_secret_access_key|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{20,}|token[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{24,})' "$PROJECT_ROOT/$f" 2>/dev/null; then
      hits="${hits}${f} "
    fi
    # Password: keep a WIDE match (quote OR bare literal >=12 non-space chars) so
    # real .env-style leaks are not missed, then drop function-call assignments
    # (password=env.get(...), must_change_password=bool(...)) which read config,
    # not credentials. Two-stage: candidate lines minus "value is identifier+("
    # lines; if any remain, it is a credential-shaped literal. This is a shape
    # heuristic — residual edges (e.g. `password: str = env.get()`) are covered
    # by scan_allow_paths.
    if grep -Ein 'password[[:space:]]*[:=][[:space:]]*[^[:space:]]{12,}' "$PROJECT_ROOT/$f" 2>/dev/null \
      | grep -viE 'password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_.]+[[:space:]]*\(' 2>/dev/null \
      | grep -qE .; then
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
  local keys key n i cmd status vout env_hint=""
  [ -f "$pf" ] || return 0
  vout="$(mktemp)"
  keys="test build lint typecheck audit sast"
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
        if [ "$status" -ne 0 ]; then
          echo "final verification command failed (exit=$status): $cmd" >&2
          cat "$vout" >&2
          # If the profile declares external services/fidelity, the failure may
          # be a missing environment rather than a code defect. Surface the
          # likely cause once so the user narrows commands.test to
          # sandbox-reproducible checks instead of chasing a phantom bug.
          if [ -z "$env_hint" ] && {
            [ -n "$(yq e '.environment.required_services // [] | .[]' "$pf" 2>/dev/null)" ] \
            || [ "$(yq e '.environment.fidelity.enabled // false' "$pf" 2>/dev/null)" = "true" ]
          }; then
            env_hint=1
            echo "  hint: profile declares external services/fidelity — this may be an environment dependency, not a code failure" >&2
            echo "  keep commands.test sandbox-reproducible; move DB/Redis/Browser/LLM tests to environment.smoke_tests / fidelity / CI" >&2
          fi
          /bin/rm -f "$vout"
          return 1
        fi
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
  out="$(cd "$PROJECT_ROOT" && gh pr create --base "$base" --head "$branch" --title "$title" --body "$body" 2>&1)" || { echo "$out" >&2; return 1; }
  printf '%s\n' "$out" | tail -1
}
