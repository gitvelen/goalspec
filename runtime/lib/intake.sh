#!/usr/bin/env bash
# intake.sh — helpers for intake capture and source provenance.

goalspec_intake_sources_file() {
  echo "$GOALSPEC_ROOT/active/intake-sources.yaml"
}

goalspec_intake_capture_file() {
  echo "$GOALSPEC_ROOT/active/intake-capture.md"
}

goalspec_constraint_suggestions_file() {
  echo "$GOALSPEC_ROOT/active/constraint-suggestions.yaml"
}

goalspec_intake_conversation_file() {
  echo "$GOALSPEC_ROOT/active/intake-conversation.md"
}

goalspec_intake_sources_init() {
  local f
  f="$(goalspec_intake_sources_file)"
  if [ ! -f "$f" ]; then
    printf 'sources: []\n' > "$f"
  fi
}

goalspec_intake_has_conversation_source() {
  local f
  f="$(goalspec_intake_sources_file)"
  [ -f "$f" ] || return 1
  [ "$(yq e '[.sources[] | select(.type == "conversation")] | length' "$f" 2>/dev/null || echo 0)" -gt 0 ]
}

goalspec_intake_has_sources() {
  local f
  f="$(goalspec_intake_sources_file)"
  [ -f "$f" ] || return 1
  [ "$(yq e '.sources | length' "$f" 2>/dev/null || echo 0)" -gt 0 ]
}

goalspec_intake_safe_name() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#_#g'
}

goalspec_intake_apply_constraint_suggestions() {
  local sf profile constraints state_file cur_hash tmp
  sf="$(goalspec_constraint_suggestions_file)"
  profile="$GOALSPEC_ROOT/project/profile.yaml"
  constraints="$GOALSPEC_ROOT/project/constraints.yaml"
  state_file="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$sf" ] || goalspec_die "constraint suggestions missing: $sf"

  sf="$sf" yq e -i '. *= (load(strenv(sf)).project_profile.merge // {})' "$profile"

  tmp="$(mktemp)"
  yq e '.project_constraints // []' "$sf" > "$tmp"
  if [ "$(yq e 'length' "$tmp" 2>/dev/null || echo 0)" -gt 0 ]; then
    tmp="$tmp" yq e -i '.constraints = ((.constraints // []) + load(strenv(tmp)) | unique_by(.id // .statement))' "$constraints"
  fi
  /bin/rm -f "$tmp"

  cur_hash="$(goalspec_constraint_suggestions_hash)"
  yq e -i ".constraint_suggestions_applied_hash = \"$cur_hash\"" "$state_file"
}

goalspec_intake_relative_path() {
  local path="$1"
  case "$path" in
    "$PROJECT_ROOT"/*) printf '%s\n' "${path#"$PROJECT_ROOT"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

goalspec_intake_add_source() {
  local src="$1"
  [ -n "$src" ] || goalspec_die "intake source path is required"

  local abs rel type hash dest_dir stamp safe snapshot candidates tmp
  if [ -e "$src" ]; then
    abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
  elif [ -e "$PROJECT_ROOT/$src" ]; then
    abs="$(cd "$(dirname "$PROJECT_ROOT/$src")" && pwd)/$(basename "$src")"
  else
    goalspec_die "intake source not found: $src"
  fi

  rel="$(goalspec_intake_relative_path "$abs")"
  if [ -f "$abs" ]; then
    type="file"
  elif [ -d "$abs" ]; then
    type="directory"
  else
    goalspec_die "intake source is not a regular file or directory: $src"
  fi

  goalspec_intake_sources_init
  dest_dir="$GOALSPEC_ROOT/artifacts/intake"
  mkdir -p "$dest_dir"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  safe="$(goalspec_intake_safe_name "$rel")"

  if [ "$type" = "file" ]; then
    snapshot="artifacts/intake/${stamp}-${safe}"
    cp "$abs" "$GOALSPEC_ROOT/$snapshot"
    hash="$(goalspec_hash_file "$GOALSPEC_ROOT/$snapshot")"
    tmp="$(mktemp)"
    yq -o=y --null-input \
      ".type = \"$type\" | .path = \"$rel\" | .snapshot_path = \"$snapshot\" | .hash = \"$hash\" | .captured_at = \"$(goalspec_now)\"" > "$tmp"
  else
    snapshot="artifacts/intake/${stamp}-${safe}-listing.txt"
    candidates="artifacts/intake/${stamp}-${safe}-text-candidates.txt"
    (
      cd "$abs" || exit 1
      find . \
        -path './.git' -prune -o \
        -path './.goalspec' -prune -o \
        -path './node_modules' -prune -o \
        -type f -print | sed 's#^\./##' | LC_ALL=C sort
    ) > "$GOALSPEC_ROOT/$snapshot"
    grep -Ei '\.(md|markdown|txt|rst|adoc|yaml|yml|json|toml|ini|cfg)$' "$GOALSPEC_ROOT/$snapshot" > "$GOALSPEC_ROOT/$candidates" || true
    hash="$(goalspec_hash_file "$GOALSPEC_ROOT/$snapshot")"
    tmp="$(mktemp)"
    yq -o=y --null-input \
      ".type = \"$type\" | .path = \"$rel\" | .snapshot_path = \"$snapshot\" | .text_candidates_path = \"$candidates\" | .hash = \"$hash\" | .captured_at = \"$(goalspec_now)\"" > "$tmp"
  fi

  yq e -i ".sources += load(\"$tmp\")" "$(goalspec_intake_sources_file)"
  /bin/rm -f "$tmp"
}

goalspec_intake_record_conversation_source() {
  goalspec_intake_sources_init
  local f tmp tpath hash=""
  f="$(goalspec_intake_sources_file)"
  if [ "$(yq e '[.sources[] | select(.type == "conversation")] | length' "$f" 2>/dev/null || echo 0)" -gt 0 ]; then
    return 0
  fi
  # Record the real on-disk transcript path when one can be located, so the
  # conversation source is traceable instead of a placeholder string.
  tpath="$(goalspec_transcript_current_path 2>/dev/null || true)"
  [ -n "$tpath" ] && [ -f "$tpath" ] && hash="$(goalspec_hash_file "$tpath")"
  tmp="$(mktemp)"
  yq -o=y --null-input \
    ".type = \"conversation\" | .path = \"${tpath:-current AI session}\" | .snapshot_path = \"active/intake-conversation.md\" | .hash = \"$hash\" | .captured_at = \"$(goalspec_now)\"" > "$tmp"
  yq e -i ".sources += load(\"$tmp\")" "$f"
  /bin/rm -f "$tmp"
}
