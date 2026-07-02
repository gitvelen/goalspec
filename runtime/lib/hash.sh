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

# Hash a non-empty stripped string. Refuses to hash empty input — an empty
# stripped value means yq failed to parse the source (corrupt/unreadable YAML),
# and hashing empty content would yield the fixed sha256 e3b0c44... that looks
# valid, letting a corrupt file pass staleness checks silently. This is the
# mechanism behind the yq-quirk silent-failure incident (memory:
# goalspec-yq-map-literal-quirk): a {key: .val} object literal that yq v4
# rejects left the stripped content empty, the empty-content hash still matched
# the recorded hash, and staleness checks passed while the real content was
# gone. Fail loudly instead. Echoes sha256:<hash> on success; returns 1 on
# empty input (stdout empty so callers comparing hashes see a mismatch).
# args: <stripped_content> <name-for-error-message>
goalspec_hash_stripped() {
  local stripped="$1" name="$2" h
  if [ -z "$stripped" ] || [ "$stripped" = "null" ]; then
    echo "${name}: hash input empty (source missing/corrupt/unparseable) — refusing to hash empty content" >&2
    return 1
  fi
  h="$(printf '%s' "$stripped" | sha256sum | awk '{print $1}')"
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
  goalspec_hash_stripped "$stripped" "contract_hash"
}

goalspec_scope_hash() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml" af="$GOALSPEC_ROOT/active/scope-amendments.yaml"
  local stripped h
  stripped="$(
    {
      printf 'allowed:\n'
      goalspec_scope_allowed_patterns | sort -u | sed 's/^/  - /'
      printf 'forbidden:\n'
      [ -f "$cf" ] && yq e -o=t '.forbidden_paths[]' "$cf" 2>/dev/null | sort -u | sed 's/^/  - /'
      printf 'amendments:\n'
      if [ -f "$af" ]; then
        yq e -o=yaml '[.amendments[]? | select(.status == "approved") | del(.old_scope_hash, .new_scope_hash)]' "$af" 2>/dev/null | sed 's/^/  /'
      else
        printf '  []\n'
      fi
    } 2>/dev/null
  )"
  if [ -z "$stripped" ]; then echo "sha256:empty"; return 0; fi
  h="$(printf '%s' "$stripped" | sha256sum | awk '{print $1}')"
  echo "sha256:${h}"
}

# Hash of the criteria content (criteria + optional_criteria) as fields of
# contract.yaml. The frozen criteria are no longer a separate file; contract.yaml
# is the single frozen source, so this hashes its criteria fields directly.
# (yq v4 here rejects {key: .val} object literals, so extract fields individually.)
goalspec_criteria_hash() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo ""; return 1; }
  local stripped
  stripped="$(
    yq e '.criteria // []' "$cf" 2>/dev/null
    yq e '.optional_criteria // []' "$cf" 2>/dev/null
  )"
  goalspec_hash_stripped "$stripped" "criteria_hash"
}

# Per-criterion content hash — the freshness basis for ONE criterion's verdict
# (scoped-reopen: a verdict stays fresh across a reopen that doesn't touch this
# criterion). Covers the criterion's semantic fields PLUS the content of every
# evidence_requirement it cites, so weakening a cited ER's runtime_boundary or
# statement — without changing IDs, criteria, or evidence records — still stales
# the verdict (closes the ER-content-drift hole that dropping the whole-contract
# hash would otherwise open). Cosmetic fields (workunit, priority) are excluded.
# Each field uses `// <default>` so absent and explicit-default hash identically.
# (yq v4 rejects {key:.val} object literals — extract per field, like above.)
goalspec_criterion_hash() {
  local cid="$1" cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo ""; return 1; }
  local stripped erefs er er_rec
  stripped="$(
    yq e ".criteria[] | select(.id == \"$cid\") | .id // \"\"" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | .statement // \"\"" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | (.evidence_requirement_refs // [])" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | (.kind // \"machine\")" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | (.required_for_completion // true)" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | (.must_not // [])" "$cf" 2>/dev/null
    yq e ".criteria[] | select(.id == \"$cid\") | (.final // false)" "$cf" 2>/dev/null
    erefs="$(yq e ".criteria[] | select(.id == \"$cid\") | (.evidence_requirement_refs // [])[]" "$cf" 2>/dev/null)"
    if [ -n "$erefs" ]; then
      while IFS= read -r er; do
        [ -z "$er" ] && continue
        er_rec="$(yq e ".evidence_requirements[] | select(.id == \"$er\")" "$cf" 2>/dev/null || true)"
        [ -n "$er_rec" ] && [ "$er_rec" != "null" ] && printf '%s\n' "$er_rec"
      done <<<"$erefs"
    fi
  )"
  goalspec_hash_stripped "$stripped" "criterion_hash[$cid]"
}

# Hash of the constraints content (constraints + allowed_paths + forbidden_paths)
# as fields of contract.yaml. Parallel to goalspec_criteria_hash.
goalspec_constraints_hash() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$cf" ] || { echo ""; return 1; }
  local stripped
  stripped="$(
    yq e '.constraints // []' "$cf" 2>/dev/null
    yq e '.allowed_paths // []' "$cf" 2>/dev/null
    yq e '.forbidden_paths // []' "$cf" 2>/dev/null
  )"
  goalspec_hash_stripped "$stripped" "constraints_hash"
}

goalspec_prompt_hash() {
  local pf="$GOALSPEC_ROOT/active/goal-driven-prompt.md"
  [ -f "$pf" ] || { echo ""; return 1; }
  local stripped
  stripped="$(sed 's/^prompt_hash: .*/prompt_hash: null/' "$pf")"
  goalspec_hash_stripped "$stripped" "prompt_hash"
}

goalspec_evidence_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/evidence.yaml"
}

# Hash only the evidence records cited by a verdict. This is the freshness
# basis for that verdict: appending unrelated evidence must not stale it, while
# mutating/deleting any cited evidence must.
goalspec_evidence_basis_hash() {
  local ef="$GOALSPEC_ROOT/active/evidence.yaml"
  local refs="" er rec stripped=""
  [ -f "$ef" ] || { echo ""; return 1; }
  if [ "$#" -gt 0 ]; then
    refs="$(printf '%s\n' "$@")"
  else
    refs="$(cat)"
  fi
  refs="$(printf '%s\n' "$refs" | sed '/^$/d' | sort -u)"
  if [ -z "$refs" ]; then
    echo "evidence_basis_hash: no evidence refs" >&2
    echo ""
    return 1
  fi
  while IFS= read -r er; do
    [ -z "$er" ] && continue
    rec="$(yq e ".evidence[] | select(.id == \"$er\")" "$ef" 2>/dev/null || true)"
    if [ -z "$rec" ] || [ "$rec" = "null" ]; then
      echo "evidence_basis_hash: evidence ref not found: $er" >&2
      echo ""
      return 1
    fi
    stripped="${stripped}--- evidence_ref: ${er}"$'\n'"${rec}"$'\n'
  done <<<"$refs"
  goalspec_hash_stripped "$stripped" "evidence_basis_hash"
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
    "$GOALSPEC_ROOT/active/constraint-suggestions.yaml" \
    "$GOALSPEC_ROOT/active/intake-sources.yaml"
}

goalspec_verdict_hash() {
  goalspec_hash_file "$GOALSPEC_ROOT/active/verdict.yaml"
}

goalspec_changed_files_fingerprint() {
  local base="$1" f full sha
  goalspec_git_changed_files "$base" | sort -u | while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      .goalspec/active/close-package.yaml|.goalspec/active/close-package.md|.goalspec/active/state.yaml) continue ;;
    esac
    full="$PROJECT_ROOT/$f"
    if [ -f "$full" ]; then
      sha="$(sha256sum "$full" | awk '{print $1}')"
      printf '%s\t%s\n' "$f" "$sha"
    else
      printf '%s\t%s\n' "$f" "deleted"
    fi
  done
}

goalspec_changed_files_hash() {
  local base fp h
  base="$(goalspec_state_get 'git.base_revision' 2>/dev/null || echo "")"
  fp="$(goalspec_changed_files_fingerprint "$base")"
  if [ -z "$fp" ]; then echo "sha256:empty"; return 0; fi
  h="$(printf '%s' "$fp" | sha256sum | awk '{print $1}')"
  echo "sha256:${h}"
}

goalspec_suggested_delivery_hash() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  [ -f "$cpf" ] || { echo ""; return 1; }
  local stripped
  stripped="$(yq e '{"commit": .commit, "pr": .pr, "delivery": .delivery}' "$cpf")"
  goalspec_hash_stripped "$stripped" "suggested_delivery_hash"
}

goalspec_close_package_hash() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  [ -f "$cpf" ] || { echo ""; return 1; }
  local stripped
  stripped="$(yq e 'del(.hashes.close_package_hash)' "$cpf")"
  goalspec_hash_stripped "$stripped" "close_package_hash"
}
