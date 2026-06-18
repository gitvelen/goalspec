#!/usr/bin/env bash
# hash.sh — content hashes used for staleness tracking.

# sha256 of a file's contents, prefixed sha256:
goalspec_hash_file() {
  local f="$1"
  [ -f "$f" ] || { echo ""; return 1; }
  local h
  h="$(sha256sum "$f" | awk '{print $1}')"
  echo "sha256:${h}"
}

# Combined hash of multiple files (e.g. all of project memory). Order-sorted.
goalspec_hash_files() {
  local out=""
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    out="${out}$(sha256sum "$f" | awk '{print $1}')"
  done
  if [ -z "$out" ]; then echo "sha256:empty"; return 0; fi
  local h
  h="$(printf '%s' "$out" | sha256sum | awk '{print $1}')"
  echo "sha256:${h}"
}

# Hash of project memory bundle (memory/constraints/regression-suite/profile/versions).
goalspec_project_memory_hash() {
  goalspec_hash_files \
    "$GOALSPEC_ROOT/project/profile.yaml" \
    "$GOALSPEC_ROOT/project/memory.yaml" \
    "$GOALSPEC_ROOT/project/constraints.yaml" \
    "$GOALSPEC_ROOT/project/regression-suite.yaml" \
    "$GOALSPEC_ROOT/project/versions.yaml"
}

goalspec_goal_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/goal.md"
}

goalspec_contract_hash() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo ""; return 1; }
  # Exclude contract_hash (self-reference) and status from the hash, since
  # freeze writes contract_hash into the file and toggles status: this would
  # otherwise make every frozen contract appear stale vs its own stored hash.
  local stripped
  stripped="$(yq e 'del(.contract_hash) | del(.status)' "$cf")"
  local h
  h="$(printf '%s' "$stripped" | sha256sum | awk '{print $1}')"
  echo "sha256:${h}"
}

goalspec_evidence_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/evidence.yaml"
}

goalspec_memory_patch_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/memory-patch.yaml"
}

goalspec_intake_capture_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/intake-capture.md"
}

goalspec_constraint_suggestions_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
}

goalspec_intake_package_hash() {
  goalspec_hash_files \
    "$GOALSPEC_ROOT/active/intake-capture.md" \
    "$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
}
