#!/usr/bin/env bash
# git.sh — git utilities for scope and dirty checks.

# Returns 0 if current directory is inside a git repo.
goalspec_git_in_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

# Get current HEAD revision (returns empty if no commit yet).
goalspec_git_head() {
  git rev-parse HEAD 2>/dev/null || echo ""
}

# List changed files vs base. Both committed and untracked/unstaged are returned.
goalspec_git_changed_files() {
  local base="$1" head
  head="$(goalspec_git_head)"
  if [ -z "$head" ]; then
    # No commits — list untracked
    git ls-files --others --exclude-standard 2>/dev/null
    return 0
  fi
  if [ -z "$base" ]; then
    # All tracked + untracked not yet committed vs HEAD
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  else
    git diff --name-only "$base" "$head" 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  fi
}

# Is the business worktree dirty? (excludes .goalspec/active compiled artifacts.)
goalspec_git_business_dirty() {
  local base files f
  base="$(goalspec_state_get '.git.base_revision // ""')"
  files="$(goalspec_git_changed_files "$base")"
  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      .goalspec/active/*|.goalspec/history/*) continue ;;
      .goalspec/goalspec|.goalspec/runtime/*|.goalspec/ai/*|.goalspec/project/*) continue ;;
      .goalspec/AGENTS.md|.goalspec/CLAUDE.md) continue ;;
      *) found=1; break ;;
    esac
  done <<<"$files"
  [ "$found" -eq 1 ]
}
