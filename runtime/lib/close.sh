#!/usr/bin/env bash
# close.sh — close-package helpers and completion gate shared by run/close.

goalspec_close_blocking_questions_count() {
  yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$GOALSPEC_ROOT/active/questions.yaml" 2>/dev/null || echo 0
}

goalspec_close_required_criteria_ids() {
  yq e '.criteria[].id' "$GOALSPEC_ROOT/active/contract.yaml" 2>/dev/null || true
}

goalspec_close_latest_verdict_field() {
  local cid="$1" field="$2" vf="$GOALSPEC_ROOT/active/verdict.yaml"
  yq e "[.verdicts[] | select(.criteria_ref == \"$cid\")] | .[-1].$field // \"\"" "$vf" 2>/dev/null || true
}

goalspec_close_all_required_pass() {
  local cid verdict missing="" bad=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    verdict="$(goalspec_close_latest_verdict_field "$cid" verdict)"
    case "$verdict" in
      pass) ;;
      "") missing="${missing}${cid} " ;;
      *) bad="${bad}${cid}=${verdict} " ;;
    esac
  done <<<"$(goalspec_close_required_criteria_ids)"
  [ -z "$missing" ] && [ -z "$bad" ]
}

goalspec_close_validate_pass_evidence() {
  local cid v_ehash cur_ehash evidence_refs n i er missing=""
  cur_ehash="$(goalspec_evidence_hash)"
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    [ "$(goalspec_close_latest_verdict_field "$cid" verdict)" = "pass" ] || { missing="${missing}${cid}:no_pass "; continue; }
    v_ehash="$(goalspec_close_latest_verdict_field "$cid" evidence_hash)"
    [ "$v_ehash" = "$cur_ehash" ] || { missing="${missing}${cid}:stale_evidence "; continue; }
    evidence_refs="$(yq e "[.verdicts[] | select(.criteria_ref == \"$cid\")] | .[-1].evidence_refs[]" "$GOALSPEC_ROOT/active/verdict.yaml" 2>/dev/null || true)"
    [ -n "$evidence_refs" ] || { missing="${missing}${cid}:no_evidence_refs "; continue; }
    while IFS= read -r er; do
      [ -z "$er" ] && continue
      if ! yq e ".evidence[] | select(.id == \"$er\") | .id" "$GOALSPEC_ROOT/active/evidence.yaml" 2>/dev/null | grep -q .; then
        missing="${missing}${cid}:missing_$er "
      fi
    done <<<"$evidence_refs"
  done <<<"$(goalspec_close_required_criteria_ids)"
  [ -z "$missing" ] || { echo "$missing"; return 1; }
}

goalspec_close_write_package() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  local md="$GOALSPEC_ROOT/active/close-package.md"
  local state_file="$GOALSPEC_ROOT/active/state.yaml"
  local goal_id goal_summary base changed_business changed_goalspec now
  local chash ehash vhash mhash changed_hash suggested_hash cphash
  goal_id="$(yq e '.active_goal_id // ""' "$state_file")"
  goal_summary="$(awk '/^## .*Intent/ { in_intent=1; next } /^## / && in_intent { exit } in_intent && NF { print; exit }' "$GOALSPEC_ROOT/active/goal.md" 2>/dev/null || true)"
  [ -n "$goal_summary" ] || goal_summary="$goal_id"
  base="$(yq e '.git.base_revision // ""' "$state_file")"
  now="$(goalspec_now)"
  chash="$(goalspec_contract_hash)"
  ehash="$(goalspec_evidence_hash)"
  vhash="$(goalspec_verdict_hash)"
  mhash="$(goalspec_memory_patch_hash)"
  changed_hash="$(goalspec_changed_files_hash)"

  changed_business="$(goalspec_git_changed_files "$base" | sort -u | grep -v '^\.goalspec/' || true)"
  changed_goalspec="$(goalspec_git_changed_files "$base" | sort -u | grep '^\.goalspec/' || true)"

  cat > "$cpf" <<YML
status: ready_to_close
generated_at: "$now"
goal_id: "$goal_id"
goal_summary: "$goal_summary"
criteria_verdicts:
YML
  local cid verdict refs
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    verdict="$(goalspec_close_latest_verdict_field "$cid" verdict)"
    refs="$(yq e "[.verdicts[] | select(.criteria_ref == \"$cid\")] | .[-1].evidence_refs // []" "$GOALSPEC_ROOT/active/verdict.yaml" 2>/dev/null || echo '[]')"
    {
      printf '  - criteria_ref: "%s"\n' "$cid"
      printf '    verdict: "%s"\n' "$verdict"
      printf '    evidence_refs:\n'
      printf '%s\n' "$refs" | yq e '.[]' - 2>/dev/null | sed 's/^/      - /' || true
    } >> "$cpf"
  done <<<"$(goalspec_close_required_criteria_ids)"

  cat >> "$cpf" <<YML
verification:
  commands: []
changed_files:
  business:
YML
  printf '%s\n' "$changed_business" | sed '/^$/d; s/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
  goalspec:
YML
  printf '%s\n' "$changed_goalspec" | sed '/^$/d; s/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
memory_patch:
  patches:
YML
  yq e '.patches // []' "$GOALSPEC_ROOT/active/memory-patch.yaml" 2>/dev/null | sed 's/^/    /' >> "$cpf"
  cat >> "$cpf" <<YML
commit:
  message: |-
    feat(goalspec): close $goal_id
pr:
  title: "Close $goal_id"
  body: |-
    Goal: $goal_summary

    Generated from .goalspec/active/close-package.yaml.
risks:
  residual: []
  follow_ups: []
hashes:
  contract_hash: "$chash"
  evidence_hash: "$ehash"
  verdict_hash: "$vhash"
  memory_patch_hash: "$mhash"
  changed_files_hash: "$changed_hash"
  suggested_delivery_hash: null
  close_package_hash: null
YML
  suggested_hash="$(goalspec_suggested_delivery_hash)"
  yq e -i ".hashes.suggested_delivery_hash = \"$suggested_hash\"" "$cpf"
  cphash="$(goalspec_close_package_hash)"
  yq e -i ".hashes.close_package_hash = \"$cphash\"" "$cpf"
  yq e -i ".close_package_hash = \"$cphash\"" "$state_file"

  cat > "$md" <<MD
# Close Package: $goal_id

Goal: $goal_summary

- Contract hash: $chash
- Evidence hash: $ehash
- Verdict hash: $vhash
- Memory patch hash: $mhash
- Changed files hash: $changed_hash
- Close package hash: $cphash

Run \`/goalspec close\` to confirm this package and authorize archive, memory update, commit, push, and PR creation.
MD
}

goalspec_close_validate_package_hashes() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  [ -f "$cpf" ] || { echo "close package missing"; return 1; }
  local bad=""
  [ "$(yq e '.hashes.contract_hash // ""' "$cpf")" = "$(goalspec_contract_hash)" ] || bad="${bad}contract_hash "
  [ "$(yq e '.hashes.evidence_hash // ""' "$cpf")" = "$(goalspec_evidence_hash)" ] || bad="${bad}evidence_hash "
  [ "$(yq e '.hashes.verdict_hash // ""' "$cpf")" = "$(goalspec_verdict_hash)" ] || bad="${bad}verdict_hash "
  [ "$(yq e '.hashes.memory_patch_hash // ""' "$cpf")" = "$(goalspec_memory_patch_hash)" ] || bad="${bad}memory_patch_hash "
  [ "$(yq e '.hashes.changed_files_hash // ""' "$cpf")" = "$(goalspec_changed_files_hash)" ] || bad="${bad}changed_files_hash "
  [ "$(yq e '.hashes.suggested_delivery_hash // ""' "$cpf")" = "$(goalspec_suggested_delivery_hash)" ] || bad="${bad}suggested_delivery_hash "
  [ "$(yq e '.hashes.close_package_hash // ""' "$cpf")" = "$(goalspec_close_package_hash)" ] || bad="${bad}close_package_hash "
  [ -z "$bad" ] || { echo "close package stale: $bad"; return 1; }
}

goalspec_close_completion_gate() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml" state_file="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$cf" ] || { echo "no contract.yaml"; return 1; }
  [ "$(yq e '.status // ""' "$cf")" = "frozen" ] || { echo "contract not frozen"; return 1; }
  [ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] || { echo "contract changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] || { echo "goal changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.goal_artifact_hash // ""' "$state_file")" = "$(goalspec_goal_artifact_hash)" ] || { echo "goal artifact changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] || { echo "criteria changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ] || { echo "constraints changed since freeze; re-freeze"; return 1; }
  [ "$(goalspec_close_blocking_questions_count)" -eq 0 ] || { echo "blocking questions unresolved"; return 1; }
  # Defensive: require at least one criterion, so an empty/unparseable criteria
  # table cannot make the pass-check vacuously succeed and trigger a close package.
  [ -n "$(goalspec_close_required_criteria_ids)" ] || { echo "no criteria found"; return 1; }
  goalspec_close_all_required_pass || { echo "required criteria do not all have pass verdicts"; return 1; }
  goalspec_close_validate_pass_evidence >/dev/null || { echo "pass verdicts lack fresh evidence"; return 1; }
  GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run || { echo "scope-check failed"; return 1; }
  local mpf="$GOALSPEC_ROOT/active/memory-patch.yaml"
  [ -f "$mpf" ] || { echo "memory-patch.yaml missing"; return 1; }
  yq e '.patches | length' "$mpf" 2>/dev/null | grep -Eq '^[0-9]+$' || { echo "memory-patch.yaml invalid"; return 1; }
}

goalspec_close_apply_memory_patch() {
  local mpf="$GOALSPEC_ROOT/active/memory-patch.yaml"
  local n_patches i pk tmp
  n_patches="$(yq e '.patches | length' "$mpf")"
  i=0
  while [ "$i" -lt "$n_patches" ]; do
    pk="$(yq e ".patches[$i].kind" "$mpf")"
    case "$pk" in
      capability)
        yq e -i ".capabilities += load(\"$mpf\").patches[$i].content" "$GOALSPEC_ROOT/project/memory.yaml"
        ;;
      decision)
        yq e -i ".decisions += load(\"$mpf\").patches[$i].content" "$GOALSPEC_ROOT/project/memory.yaml"
        ;;
      constraint)
        yq e -i ".constraints += load(\"$mpf\").patches[$i].content" "$GOALSPEC_ROOT/project/constraints.yaml"
        ;;
      regression)
        tmp="$(mktemp)"
        yq e ".patches[$i].content + {\"status\":\"locked\"}" "$mpf" > "$tmp"
        yq e -i ".regressions += load(\"$tmp\")" "$GOALSPEC_ROOT/project/regression-suite.yaml"
        /bin/rm -f "$tmp"
        ;;
    esac
    i=$((i+1))
  done
}

goalspec_close_next_history_version() {
  local latest_v next_n
  latest_v="$(yq e '.versions | length' "$GOALSPEC_ROOT/project/versions.yaml" 2>/dev/null || echo 0)"
  next_n=$((latest_v+1))
  printf 'v%04d\n' "$next_n"
}

goalspec_close_archive_active() {
  local vname="$1" hdir="$GOALSPEC_ROOT/history/$vname" f
  mkdir -p "$hdir"
  for f in goal.md goal.yaml criteria.yaml constraints.yaml contract.yaml goal-driven-prompt.md evidence.yaml verdict.yaml trace.yaml regressions.yaml memory-patch.yaml questions.yaml reviews.yaml state.yaml close-package.yaml close-package.md; do
    [ -f "$GOALSPEC_ROOT/active/$f" ] && cp "$GOALSPEC_ROOT/active/$f" "$hdir/$f"
  done
}
