#!/usr/bin/env bash
# common.sh — shared helpers for goalspec runtime.
# Sourced by the dispatch entry and each command.

set -uo pipefail

# Resolve .goalspec project root (the dir containing .goalspec/).
# Sets GOALSPEC_ROOT (the .goalspec dir) and PROJECT_ROOT (parent).
goalspec_find_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.goalspec" ] && [ -f "$dir/.goalspec/runtime/lib/common.sh" ]; then
      GOALSPEC_ROOT="$dir/.goalspec"
      PROJECT_ROOT="$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  GOALSPEC_ROOT=""
  PROJECT_ROOT=""
  return 1
}

goalspec_die() {
  echo "goalspec: error: $*" >&2
  exit 1
}

goalspec_active_dir() { echo "$GOALSPEC_ROOT/active"; }
goalspec_project_dir() { echo "$GOALSPEC_ROOT/project"; }
goalspec_history_dir() { echo "$GOALSPEC_ROOT/history"; }
goalspec_artifacts_dir() { echo "$GOALSPEC_ROOT/artifacts"; }
goalspec_runtime_dir() { echo "$GOALSPEC_ROOT/runtime"; }

# require that we are inside an initialized goalspec project.
goalspec_require_init() {
  goalspec_find_root || goalspec_die "not a goalspec project (run '.goalspec/goalspec init' in a git repo first)"
}

# yq wrapper that operates on a file in place or reads. Use `yq e`.
goalspec_yq() { yq e "$@"; }

# read a single value from a yaml file. Returns empty string if missing.
goalspec_yaml_get() {
  local file="$1" expr="$2"
  [ -f "$file" ] || { echo ""; return 0; }
  yq e "$expr" "$file" 2>/dev/null
}

# Write a yaml value at path (creates nodes as needed).
goalspec_yaml_set() {
  local file="$1" expr="$2" value="$3"
  yq e "${expr} = \"${value}\"" -i "$file"
}

# Current timestamp ISO 8601 UTC.
goalspec_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Generate a fresh goal id like GOAL-YYYYMMDD-NNN. Always produces a NEW id:
# the sequence counts prior versions in project/versions.yaml sharing today's
# date, so a goal opened from `closed` on the same day as the previous close
# increments, and a new day starts at 001. It must never reuse the stale
# active_goal_id that close leaves behind in state.yaml — that made every
# change share one id and made versions.yaml ambiguous.
goalspec_new_goal_id() {
  local date prefix versions max gid n
  date="$(date -u +%Y%m%d)"
  prefix="GOAL-${date}-"
  versions="$GOALSPEC_ROOT/project/versions.yaml"
  max=0
  if [ -f "$versions" ]; then
    while IFS= read -r gid; do
      case "$gid" in
        "${prefix}"*)
          n="${gid#"${prefix}"}"
          case "$n" in
            ''|*[!0-9]*) ;;
            *) if [ "$n" -gt "$max" ]; then max="$n"; fi ;;
          esac
          ;;
      esac
    done <<EOF
$(yq e '.versions[].goal_id' "$versions" 2>/dev/null)
EOF
  fi
  printf 'GOAL-%s-%03d\n' "$date" "$((max+1))"
}

# Reset the active workspace to clean templates for a brand-new goal. Wipes
# EVERY prior-change artifact under active/ (contract/criteria/evidence/verdict/
# reviews/etc., not just the intake files), re-seeds from templates, and stamps
# the freshly-minted goal id. Shared by `start` (ensure_active_goal) and
# `new-goal` so the two entry points can never diverge on what a fresh active/
# looks like — and so a prior, already-closed change's frozen contract cannot
# leak into the next change (compile reuses contract.yaml only when absent).
goalspec_reset_active_workspace() {
  local active="$GOALSPEC_ROOT/active" tpl="$GOALSPEC_ROOT/runtime/templates/active" gid
  find "$active" -mindepth 1 -type f -delete 2>/dev/null || true
  cp "$tpl"/* "$active"/
  gid="$(goalspec_new_goal_id)"
  yq e -i ".active_goal_id = \"$gid\"" "$active/state.yaml"
  yq e -i ".status = \"spec_drafting\"" "$active/state.yaml"
  yq e -i ".git.base_revision = \"$(goalspec_git_head)\"" "$active/state.yaml"
  yq e -i ".git.current_revision = \"$(goalspec_git_head)\"" "$active/state.yaml"
  yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$active/state.yaml"
}

# Append a yaml document map to a list file under a key. Usage: append_list file key yamlblock
goalspec_append_list() {
  local file="$1" key="$2" block="$3"
  if [ ! -f "$file" ]; then
    printf '%s: []\n' "$key" >"$file"
  fi
  # ensure the key exists as a list
  if [ "$(yq e ".${key} == null" "$file")" = "true" ]; then
    yq e -i ".${key} = []" "$file"
  fi
  # append via 0-th of split doc
  printf '%s\n' "$block" | yq e -o=json '.' - | while read -r obj; do :; done
  # simpler: use yq '*=+' style with a temporary merge
  local tmp
  tmp="$(mktemp)"
  printf '%s\n---\n' "$block" >"$tmp"
  yq e -i ".${key} += load(\"$tmp\")" "$file"
  /bin/rm -f "$tmp"
}

# Initialize an empty active yaml list file.
goalspec_init_list_file() {
  local file="$1" key="$2"
  if [ ! -f "$file" ]; then
    printf '%s: []\n' "$key" >"$file"
  fi
}
