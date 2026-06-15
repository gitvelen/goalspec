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

# Generate goal id like GOAL-YYYYMMDD-001
goalspec_new_goal_id() {
  local date part
  date="$(date -u +%Y%m%d)"
  part="$(goalspec_yaml_get "$(goalspec_active_dir)/state.yaml" '.active_goal_id' || echo "")"
  # yq returns the literal "null" for an unset scalar; treat that as no id.
  if [ -z "$part" ] || [ "$part" = "null" ]; then
    echo "GOAL-${date}-001"
  else
    echo "$part"
  fi
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
