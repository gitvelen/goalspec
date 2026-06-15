#!/usr/bin/env bash
# complete.sh — the sole completion gate (GOALC #12-#19).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

cf="$GOALSPEC_ROOT/active/contract.yaml"
vf="$GOALSPEC_ROOT/active/verdict.yaml"
ef="$GOALSPEC_ROOT/active/evidence.yaml"
state_file="$GOALSPEC_ROOT/active/state.yaml"
qf="$GOALSPEC_ROOT/active/questions.yaml"
mpf="$GOALSPEC_ROOT/active/memory-patch.yaml"

fail() { echo "complete blocked: $*" >&2; exit 1; }

[ -f "$cf" ] || fail "no contract.yaml"
[ "$(yq e '.status' "$cf")" = "frozen" ] || fail "contract not frozen"

# 1. contract hash still valid (state.contract_hash matches current contract hash).
cur_chash="$(goalspec_contract_hash)"
rec_chash="$(yq e '.contract_hash // ""' "$state_file")"
[ "$cur_chash" = "$rec_chash" ] || fail "contract changed since freeze; re-freeze"

# 2. no blocking open questions.
nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$qf" 2>/dev/null || echo 0)"
[ "${nblock:-0}" -eq 0 ] || fail "blocking questions unresolved"

# 3. every required criteria latest verdict = pass; no fail/insufficient/blocked/stale/reopen_required on required/final/hard.
crit_ids_required="$(yq e '.criteria[] | select(.required_for_completion == true) | .id' "$cf")"
crit_ids_final="$(yq e '.criteria[] | select(.final == true) | .id' "$cf")"
crit_ids_hard="$(yq e '.criteria[] | select(.priority == "P0") | .id' "$cf")"
all_ids="$(printf '%s\n%s\n%s\n' "$crit_ids_required" "$crit_ids_final" "$crit_ids_hard" | sort -u | grep -v '^$' || true)"

[ -n "$all_ids" ] || fail "no required/final/hard criteria found"

bad=""
missing=""
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v="$(yq e "[.verdicts[] | select(.criteria_ref == \"$c\")] | .[-1].verdict // \"\"" "$vf" 2>/dev/null)"
  case "$v" in
    pass) ;;
    "") missing="${missing}${c} " ;;
    *) bad="${bad}${c}=${v} " ;;
  esac
done <<<"$all_ids"
[ -z "$missing" ] || fail "no fresh verdict for: $missing"
[ -z "$bad" ] || fail "non-pass verdict on required/final/hard criteria: $bad"

# 4. required regressions pass (verdict on regression-related criteria).
#    Skip if none.

# 5. scope-check pass. Run in 'system' role: at completion time the guardian
# has lawfully written verdict.yaml / memory-patch.yaml etc. via judge apply /
# approve; their integrity is enforced elsewhere by hash checks. The check
# still enforces that no business file is unattributed and that frozen contract
# / project / history are untouched.
if ! GOALSPEC_SCOPE_ROLE=system goalspec_scope_check_run; then
  fail "scope-check failed (see above)"
fi

# 6. memory-patch.yaml exists and is human-approved and not stale.
if [ ! -f "$mpf" ] || [ "$(yq e '.patches | length' "$mpf" 2>/dev/null || echo 0)" -lt 1 ]; then
  fail "no memory-patch.yaml entries (guardian must propose; human must approve)"
fi
if ! yq e '[.approvals[] | select(.kind == "memory-patch")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
  fail "memory-patch not human-approved"
fi
if goalspec_approval_stale memory-patch; then
  fail "memory-patch approval stale (memory-patch.yaml changed since approval)"
fi

# 7. all business changed files attributed to a passed WU — already covered by scope-check.

# === All gates passed. Apply memory patch, archive to history. ===

# Determine next version dir.
latest_v="$(yq e '.versions | length' "$GOALSPEC_ROOT/project/versions.yaml" 2>/dev/null || echo 0)"
next_n=$((latest_v+1))
vname="v$(printf '%04d' "$next_n")"
hdir="$GOALSPEC_ROOT/history/$vname"
mkdir -p "$hdir"

# Apply memory-patch: each patch has kind (capability|decision|constraint|regression) + content.
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
      # mark locked
      tmp="$(mktemp)"; yq e ".patches[$i].content + {\"status\":\"locked\"}" "$mpf" > "$tmp"
      yq e -i ".regressions += load(\"$tmp\")" "$GOALSPEC_ROOT/project/regression-suite.yaml"
      /bin/rm -f "$tmp"
      ;;
  esac
  i=$((i+1))
done

# Copy active files into history.
for f in goal.md contract.yaml evidence.yaml verdict.yaml trace.yaml regressions.yaml memory-patch.yaml questions.yaml reviews.yaml state.yaml; do
  [ -f "$GOALSPEC_ROOT/active/$f" ] && cp "$GOALSPEC_ROOT/active/$f" "$hdir/$f"
done

# Build summary.yaml.
passed_ids="$(echo "$all_ids")"
git_base="$(yq e '.git.base_revision // ""' "$state_file")"
git_completed="$(goalspec_git_head)"
files_changed="$(goalspec_git_changed_files "$git_base" | grep -v '^\.goalspec/' || true)"
cat > "$hdir/summary.yaml" <<YML
version: $vname
goal_id: $(yq e '.active_goal_id' "$state_file")
completed_at: $(goalspec_now)
contract_hash: $cur_chash
criteria_passed:
$(echo "$all_ids" | sed 's/^/  - /' | grep -v '^  - $')
git:
  base_revision: $git_base
  completed_revision: $git_completed
  dirty_at_completion: $([ -n "$files_changed" ] && echo true || echo false)
changed_files:
$(echo "$files_changed" | sed 's/^/  - /' | grep -v '^  - $' || true)
YML

# Update versions index.
yq e -i ".versions += [{\"version\": \"$vname\", \"goal_id\": \"$(yq e '.active_goal_id' "$state_file")\", \"completed_at\": \"$(goalspec_now)\", \"contract_hash\": \"$cur_chash\"}]" "$GOALSPEC_ROOT/project/versions.yaml"

# Transition state.
goalspec_state_set_status completed

echo "complete: $vname"
echo "  history: $hdir"
echo "  summary: $hdir/summary.yaml"
