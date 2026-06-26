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

goalspec_close_criterion_pass_blocker() {
  local cid="$1"
  local cur_chash cur_ehash verdict v_chash v_ehash evidence_refs er e_chash
  cur_chash="$(goalspec_contract_hash)"
  cur_ehash="$(goalspec_evidence_hash)"
  verdict="$(goalspec_close_latest_verdict_field "$cid" verdict)"
  [ "$verdict" = "pass" ] || { echo "no_pass"; return 1; }
  v_chash="$(goalspec_close_latest_verdict_field "$cid" contract_hash)"
  [ "$v_chash" = "$cur_chash" ] || { echo "stale_contract"; return 1; }
  v_ehash="$(goalspec_close_latest_verdict_field "$cid" evidence_hash)"
  [ "$v_ehash" = "$cur_ehash" ] || { echo "stale_evidence"; return 1; }
  evidence_refs="$(yq e "[.verdicts[] | select(.criteria_ref == \"$cid\")] | .[-1].evidence_refs[]" "$GOALSPEC_ROOT/active/verdict.yaml" 2>/dev/null || true)"
  [ -n "$evidence_refs" ] || { echo "no_evidence_refs"; return 1; }
  while IFS= read -r er; do
    [ -z "$er" ] && continue
    if ! yq e ".evidence[] | select(.id == \"$er\") | .id" "$GOALSPEC_ROOT/active/evidence.yaml" 2>/dev/null | grep -q .; then
      echo "missing_$er"
      return 1
    fi
    e_chash="$(yq e ".evidence[] | select(.id == \"$er\") | .contract_hash // \"\"" "$GOALSPEC_ROOT/active/evidence.yaml" 2>/dev/null || true)"
    [ "$e_chash" = "$cur_chash" ] || { echo "stale_evidence_contract_$er"; return 1; }
  done <<<"$evidence_refs"
}

goalspec_close_criterion_has_fresh_pass() {
  goalspec_close_criterion_pass_blocker "$1" >/dev/null
}

# Fingerprint of the current verdict state in contract order. It includes the
# latest verdict basis and fresh-pass blocker so stale pass -> fresh pass counts
# as real progress after reopen/refreeze.
goalspec_close_verdict_fingerprint() {
  local cid verdict v_chash v_ehash blocker completion fp=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    verdict="$(goalspec_close_latest_verdict_field "$cid" verdict)"
    v_chash="$(goalspec_close_latest_verdict_field "$cid" contract_hash)"
    v_ehash="$(goalspec_close_latest_verdict_field "$cid" evidence_hash)"
    if blocker="$(goalspec_close_criterion_pass_blocker "$cid")"; then
      completion="fresh_pass"
    else
      completion="$blocker"
    fi
    fp="${fp}${cid}:verdict=${verdict}:contract=${v_chash}:evidence=${v_ehash}:completion=${completion}|"
  done <<<"$(goalspec_close_required_criteria_ids)"
  printf '%s' "$fp"
}

goalspec_run_loop_stalled_current() {
  local state_file="$GOALSPEC_ROOT/active/state.yaml" fp ehash prev_fp prev_ehash
  [ "$(yq e '.run_loop.last_outcome // ""' "$state_file" 2>/dev/null)" = "stalled" ] || return 1
  prev_fp="$(yq e '.run_loop.last_fingerprint // ""' "$state_file" 2>/dev/null || echo "")"
  prev_ehash="$(yq e '.run_loop.last_evidence_hash // ""' "$state_file" 2>/dev/null || echo "")"
  [ -n "$prev_fp" ] && [ "$prev_fp" != "null" ] || return 0
  [ -n "$prev_ehash" ] && [ "$prev_ehash" != "null" ] || return 0
  fp="$(goalspec_close_verdict_fingerprint)"
  ehash="$(goalspec_evidence_hash)"
  [ "$fp" = "$prev_fp" ] && [ "$ehash" = "$prev_ehash" ]
}

goalspec_run_loop_clear_obsolete_stalled() {
  local state_file="$GOALSPEC_ROOT/active/state.yaml"
  [ "$(yq e '.run_loop.last_outcome // ""' "$state_file" 2>/dev/null)" = "stalled" ] || return 0
  goalspec_run_loop_stalled_current && return 0
  yq e -i '.run_loop.last_outcome = null | .run_loop.stall_count = 0' "$state_file"
}

goalspec_close_all_required_pass() {
  local cid blocker missing="" bad=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    if ! blocker="$(goalspec_close_criterion_pass_blocker "$cid")"; then
      case "$blocker" in
        no_pass) missing="${missing}${cid} " ;;
        *) bad="${bad}${cid}:${blocker} " ;;
      esac
    fi
  done <<<"$(goalspec_close_required_criteria_ids)"
  [ -z "$missing" ] && [ -z "$bad" ]
}

goalspec_close_validate_pass_evidence() {
  local cid blocker missing=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    if ! blocker="$(goalspec_close_criterion_pass_blocker "$cid")"; then
      missing="${missing}${cid}:${blocker} "
    fi
  done <<<"$(goalspec_close_required_criteria_ids)"
  [ -z "$missing" ] || { echo "$missing"; return 1; }
}

goalspec_close_readiness_blockers() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml" state_file="$GOALSPEC_ROOT/active/state.yaml"
  local blockers="" mpf="$GOALSPEC_ROOT/active/memory-patch.yaml"
  [ -f "$cf" ] || { echo "contract_missing"; return 0; }
  [ "$(yq e '.status // ""' "$cf")" = "frozen" ] || blockers="${blockers}contract_not_frozen "
  [ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] || blockers="${blockers}contract_stale "
  [ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] || blockers="${blockers}goal_stale "
  [ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] || blockers="${blockers}criteria_stale "
  [ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ] || blockers="${blockers}constraints_stale "
  goalspec_scope_ensure_state_hash || blockers="${blockers}scope_stale "
  [ "$(goalspec_close_blocking_questions_count)" -eq 0 ] || blockers="${blockers}blocking_questions "
  [ -n "$(goalspec_close_required_criteria_ids)" ] || blockers="${blockers}criteria_missing "
  goalspec_close_all_required_pass || blockers="${blockers}criteria_unmet "
  goalspec_close_validate_pass_evidence >/dev/null || blockers="${blockers}pass_evidence_invalid "
  if ! GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run >/dev/null 2>&1; then
    blockers="${blockers}scope_projection "
  fi
  [ -f "$mpf" ] || blockers="${blockers}memory_patch_missing "
  yq e '.patches | length' "$mpf" 2>/dev/null | grep -Eq '^[0-9]+$' || blockers="${blockers}memory_patch_invalid "
  printf '%s\n' "$blockers" | sed 's/[[:space:]]*$//'
}

goalspec_close_readiness_pass() {
  [ -z "$(goalspec_close_readiness_blockers)" ]
}

goalspec_close_readiness_print() {
  local blockers="$1"
  echo "CLOSE_PACKAGE_READY: false"
  echo "CLOSE_BLOCKERS: ${blockers:-unknown}"
  case " $blockers " in
    *" scope_projection "*)
      GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run >/dev/null 2>&1 || goalspec_scope_print_suggestions
      echo "NEXT_USER_ACTION: Treat scope as a Constraints projection issue: run goalspec scope amend if the paths still serve the current Goal without changing semantics; use /goalspec reopen only if Goal, Criteria, or semantic Constraints changed."
      ;;
    *" scope_stale "*)
      echo "NEXT_USER_ACTION: Run goalspec scope amend with a reason, then run /goalspec run again to regenerate close readiness."
      ;;
    *" memory_patch_missing "*|*" memory_patch_invalid "*)
      echo "NEXT_USER_ACTION: Fix .goalspec/active/memory-patch.yaml, then run /goalspec run again."
      ;;
    *" criteria_unmet "*|*" pass_evidence_invalid "*)
      echo "NEXT_USER_ACTION: Resolve stale or missing Criteria verdict/evidence, then run /goalspec run again."
      ;;
    *)
      echo "NEXT_USER_ACTION: Fix the listed close-readiness blocker, then run /goalspec run again."
      ;;
  esac
}

goalspec_close_write_package() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  local md="$GOALSPEC_ROOT/active/close-package.md"
  local state_file="$GOALSPEC_ROOT/active/state.yaml"
  local goal_id goal_summary base changed_business changed_goalspec now
  local chash shash ehash vhash mhash changed_hash suggested_hash cphash
  local delivery_mode delivery_remote delivery_base creates_pr
  local pf vtmp
  goal_id="$(yq e '.active_goal_id // ""' "$state_file")"
  goal_summary="$(awk '/^## .*Intent/ { in_intent=1; next } /^## / && in_intent { exit } in_intent && NF { print; exit }' "$GOALSPEC_ROOT/active/goal.md" 2>/dev/null || true)"
  [ -n "$goal_summary" ] || goal_summary="$goal_id"
  base="$(yq e '.git.base_revision // ""' "$state_file")"
  now="$(goalspec_now)"
  chash="$(goalspec_contract_hash)"
  shash="$(goalspec_scope_hash)"
  ehash="$(goalspec_evidence_hash)"
  vhash="$(goalspec_verdict_hash)"
  mhash="$(goalspec_memory_patch_hash)"
  changed_hash="$(goalspec_changed_files_hash)"
  delivery_mode="$(goalspec_delivery_mode)"
  case "$delivery_mode" in invalid:*) delivery_mode="github_pr" ;; esac
  delivery_remote="$(goalspec_git_remote)"
  delivery_base="$(goalspec_git_default_branch)"
  [ "$delivery_mode" = "github_pr" ] && creates_pr=true || creates_pr=false

  changed_business="$(goalspec_git_changed_files "$base" | sort -u | while IFS= read -r f; do
    [ -z "$f" ] && continue
    goalspec_git_is_framework_file "$f" && continue
    printf '%s\n' "$f"
  done)"
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
readiness:
  criteria_ready: true
  scope_projection_ready: true
  memory_ready: true
  blockers: []
  scope_hash: "$shash"
  changed_files_hash: "$changed_hash"
changed_files:
  business:
YML
  printf '%s\n' "$changed_business" | sed '/^$/d; s/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
  goalspec:
YML
  printf '%s\n' "$changed_goalspec" | sed '/^$/d; s/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
scope:
  allowed_paths:
YML
  goalspec_scope_allowed_patterns | sort -u | sed 's/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
  forbidden_paths:
YML
  goalspec_scope_forbidden_patterns | sort -u | sed 's/^/    - /' >> "$cpf"
  cat >> "$cpf" <<YML
  amendments:
YML
  yq e '.amendments // []' "$GOALSPEC_ROOT/active/scope-amendments.yaml" 2>/dev/null | sed 's/^/    /' >> "$cpf"
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
delivery:
  mode: "$delivery_mode"
  remote: "${delivery_remote:-}"
  base_branch: "${delivery_base:-}"
  creates_pr: $creates_pr
risks:
  residual: []
  follow_ups: []
hashes:
  contract_hash: "$chash"
  scope_hash: "$shash"
  evidence_hash: "$ehash"
  verdict_hash: "$vhash"
  memory_patch_hash: "$mhash"
  changed_files_hash: "$changed_hash"
  suggested_delivery_hash: null
  close_package_hash: null
YML

  # Populate verification.commands from the project profile — the same commands
  # final verification runs at /goalspec close. exit_code/summary are null here:
  # the commands run during close, not at close-package generation time.
  pf="$GOALSPEC_ROOT/project/profile.yaml"
  if [ -f "$pf" ]; then
    vtmp="$(mktemp)"
    yq e -o=yaml '[ ((.commands.test // []) + (.commands.build // []) + (.commands.lint // []) + (.commands.typecheck // []))[] | {"command": ., "exit_code": null, "summary": "runs during /goalspec close final verification"} ] | map(select(.command != null))' "$pf" > "$vtmp"
    yq e -i ".verification.commands = load(\"$vtmp\")" "$cpf"
    /bin/rm -f "$vtmp"
  fi

  suggested_hash="$(goalspec_suggested_delivery_hash)"
  yq e -i ".hashes.suggested_delivery_hash = \"$suggested_hash\"" "$cpf"
  cphash="$(goalspec_close_package_hash)"
  yq e -i ".hashes.close_package_hash = \"$cphash\"" "$cpf"
  yq e -i ".close_package_hash = \"$cphash\"" "$state_file"

  cat > "$md" <<MD
# Close Package: $goal_id

Goal: $goal_summary

- Contract hash: $chash
- Scope hash: $shash
- Evidence hash: $ehash
- Verdict hash: $vhash
- Memory patch hash: $mhash
- Changed files hash: $changed_hash
- Delivery mode: $delivery_mode
- Delivery remote: ${delivery_remote:-none}
- Delivery base branch: ${delivery_base:-none}
- Creates PR: $creates_pr
- Close package hash: $cphash

Run \`/goalspec close\` to confirm this package and authorize the configured delivery mode.
MD
}

goalspec_close_validate_package_hashes() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  [ -f "$cpf" ] || { echo "close package missing"; return 1; }
  local bad=""
  [ "$(yq e '.hashes.contract_hash // ""' "$cpf")" = "$(goalspec_contract_hash)" ] || bad="${bad}contract_hash "
  [ "$(yq e '.hashes.scope_hash // ""' "$cpf")" = "$(goalspec_scope_hash)" ] || bad="${bad}scope_hash "
  [ "$(yq e '.hashes.evidence_hash // ""' "$cpf")" = "$(goalspec_evidence_hash)" ] || bad="${bad}evidence_hash "
  [ "$(yq e '.hashes.verdict_hash // ""' "$cpf")" = "$(goalspec_verdict_hash)" ] || bad="${bad}verdict_hash "
  [ "$(yq e '.hashes.memory_patch_hash // ""' "$cpf")" = "$(goalspec_memory_patch_hash)" ] || bad="${bad}memory_patch_hash "
  [ "$(yq e '.hashes.changed_files_hash // ""' "$cpf")" = "$(goalspec_changed_files_hash)" ] || bad="${bad}changed_files_hash "
  [ "$(yq e '.hashes.suggested_delivery_hash // ""' "$cpf")" = "$(goalspec_suggested_delivery_hash)" ] || bad="${bad}suggested_delivery_hash "
  [ "$(yq e '.hashes.close_package_hash // ""' "$cpf")" = "$(goalspec_close_package_hash)" ] || bad="${bad}close_package_hash "
  [ -z "$bad" ] || { echo "close package stale: $bad"; return 1; }
}

goalspec_close_package_has_readiness() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml"
  [ "$(yq e 'has("readiness")' "$cpf" 2>/dev/null)" = "true" ]
}

goalspec_close_validate_readiness_snapshot() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml" bad=""
  goalspec_close_package_has_readiness || { echo "close package has no readiness snapshot"; return 1; }
  [ "$(yq e '.readiness.criteria_ready // false' "$cpf")" = "true" ] || bad="${bad}criteria_ready "
  [ "$(yq e '.readiness.scope_projection_ready // false' "$cpf")" = "true" ] || bad="${bad}scope_projection_ready "
  [ "$(yq e '.readiness.memory_ready // false' "$cpf")" = "true" ] || bad="${bad}memory_ready "
  [ "$(yq e '.readiness.scope_hash // ""' "$cpf")" = "$(goalspec_scope_hash)" ] || bad="${bad}scope_hash "
  [ "$(yq e '.readiness.changed_files_hash // ""' "$cpf")" = "$(goalspec_changed_files_hash)" ] || bad="${bad}changed_files_hash "
  [ "$(yq e '.readiness.blockers | length' "$cpf" 2>/dev/null || echo 1)" = "0" ] || bad="${bad}blockers "
  [ -z "$bad" ] || { echo "close package readiness stale: $bad"; return 1; }
}

goalspec_close_recheck_changed_files_hash() {
  local cpf="$GOALSPEC_ROOT/active/close-package.yaml" expected
  expected="$(yq e '.hashes.changed_files_hash // ""' "$cpf")"
  [ "$expected" = "$(goalspec_changed_files_hash)" ] || {
    echo "changed files changed during final verification; run /goalspec run to regenerate the close package"
    return 1
  }
}

goalspec_close_completion_gate() {
  local cf="$GOALSPEC_ROOT/active/contract.yaml" state_file="$GOALSPEC_ROOT/active/state.yaml"
  [ -f "$cf" ] || { echo "no contract.yaml"; return 1; }
  [ "$(yq e '.status // ""' "$cf")" = "frozen" ] || { echo "contract not frozen"; return 1; }
  [ "$(yq e '.contract_hash // ""' "$state_file")" = "$(goalspec_contract_hash)" ] || { echo "contract changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.goal_hash // ""' "$state_file")" = "$(goalspec_goal_hash)" ] || { echo "goal changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.criteria_hash // ""' "$state_file")" = "$(goalspec_criteria_hash)" ] || { echo "criteria changed since freeze; re-freeze"; return 1; }
  [ "$(yq e '.constraints_hash // ""' "$state_file")" = "$(goalspec_constraints_hash)" ] || { echo "constraints changed since freeze; re-freeze"; return 1; }
  goalspec_scope_ensure_state_hash || { echo "effective scope changed since last approval; run goalspec scope amend with a reason"; return 1; }
  [ "$(goalspec_close_blocking_questions_count)" -eq 0 ] || { echo "blocking questions unresolved"; return 1; }
  # Defensive: require at least one criterion, so an empty/unparseable criteria
  # table cannot make the pass-check vacuously succeed and trigger a close package.
  [ -n "$(goalspec_close_required_criteria_ids)" ] || { echo "no criteria found"; return 1; }
  goalspec_close_all_required_pass || { echo "required criteria do not all have fresh pass verdicts"; return 1; }
  goalspec_close_validate_pass_evidence >/dev/null || { echo "pass verdicts are stale or lack fresh evidence"; return 1; }
  GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run || {
    goalspec_scope_print_suggestions
    echo "scope-check failed"
    return 1
  }
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
  for f in goal.md contract.yaml goal-driven-prompt.md evidence.yaml verdict.yaml trace.yaml regressions.yaml memory-patch.yaml questions.yaml reviews.yaml state.yaml close-package.yaml close-package.md reopen-impact.yaml harness-improvement-candidate.yaml scope-amendments.yaml; do
    [ -f "$GOALSPEC_ROOT/active/$f" ] && cp "$GOALSPEC_ROOT/active/$f" "$hdir/$f"
  done
}

# Vacate active/ after a successful close: delete every business artifact so the
# just-closed goal's snapshot does not linger in active/. A lingering closed
# snapshot is exactly what lets an external "restore/sync" resurrect a stale
# goal over the next in-flight one (see the velentrade postmortem — gitignoring
# .goalspec/ alone is insufficient if the old snapshot stays on disk to be
# copied back). state.yaml stays as a tombstone (status=closed + active_goal_id
# + close.*/git.*) so `status` and history linkage stay queryable until the next
# start resets the workspace.
goalspec_close_vacate_active() {
  local active="$GOALSPEC_ROOT/active" f
  for f in goal.md goal.yaml contract.yaml contract-review.yaml criteria.yaml constraints.yaml constraint-suggestions.yaml goal-driven-prompt.md evidence.yaml verdict.yaml trace.yaml regressions.yaml memory-patch.yaml questions.yaml reviews.yaml close-package.yaml close-package.md reopen-impact.yaml harness-improvement-candidate.yaml scope-amendments.yaml intake-capture.md intake-conversation.md intake-review.yaml intake-sources.yaml; do
    [ -f "$active/$f" ] && /bin/rm -f "$active/$f"
  done
}
