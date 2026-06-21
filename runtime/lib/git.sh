#!/usr/bin/env bash
# git.sh — git utilities for scope and dirty checks.

# Returns 0 if current directory is inside a git repo.
goalspec_git_in_repo() {
  git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1
}

# Get current HEAD revision (returns empty if no commit yet).
goalspec_git_head() {
  git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo ""
}

# Framework-managed metadata and AI collaboration guides are not business files.
goalspec_git_is_framework_file() {
  local f="$1"
  case "$f" in
    .goalspec/*|AGENTS.md|CLAUDE.md) return 0 ;;
    *) return 1 ;;
  esac
}

# List changed files vs base. Both committed and untracked/unstaged are returned.
goalspec_git_changed_files() {
  local base="$1" head
  # yq may return the literal string "null" for an unset YAML scalar; treat it
  # the same as an empty base so we fall back to "diff vs HEAD + untracked".
  [ "$base" = "null" ] && base=""
  head="$(goalspec_git_head)"
  if [ -z "$head" ]; then
    # No commits — list untracked
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null
    return 0
  fi
  if [ -z "$base" ]; then
    # All tracked + untracked not yet committed vs HEAD
    git -C "$PROJECT_ROOT" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null
  else
    git -C "$PROJECT_ROOT" diff --name-only "$base" "$head" 2>/dev/null
    git -C "$PROJECT_ROOT" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null
  fi
}

# Is the business worktree dirty? (excludes .goalspec/active compiled artifacts.)
goalspec_git_business_dirty() {
  local base files f
  base="$(goalspec_state_get 'git.base_revision')"
  files="$(goalspec_git_changed_files "$base")"
  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if goalspec_git_is_framework_file "$f"; then continue; fi
    found=1; break
  done <<<"$files"
  [ "$found" -eq 1 ]
}
