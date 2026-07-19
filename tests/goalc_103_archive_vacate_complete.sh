#!/usr/bin/env bash
# GOALC #103: close archive/vacate must be COMPLETE, not allowlist-based.
# Regression for the double-allowlist gap: archive_active and vacate_active both
# missed intake-capture review artifacts (contract-review-v2.yaml,
# intake-capture-review-v2.yaml), so they were neither archived into history/
# nor cleared from active/ — the v0009 velentrade incident. Both functions now
# glob all of active/ so new artifact types are captured automatically. Also
# pins the vname-guard judgment rule from commands/close.sh (Bug B).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-103
A="$REPO/.goalspec/active"; H="$REPO/.goalspec/history"
mkdir -p "$A/artifacts" "$H"
# Seed a mix: an old-allowlist file, NON-allowlist review files, a subdir, and
# the state.yaml tombstone (which vacate must keep).
printf 'x\n' > "$A/contract.yaml"
printf 'x\n' > "$A/contract-review-v2.yaml"
printf 'x\n' > "$A/intake-capture-review-v2.yaml"
printf 'x\n' > "$A/artifacts/blob.bin"
printf 'status: closed\n' > "$A/state.yaml"

# archive_active v0042 must copy EVERYTHING (incl. non-allowlist files + the
# subdir) into history/v0042/.
GOALSPEC_ROOT="$REPO/.goalspec" PROJECT_ROOT="$REPO" bash -c '
  . "'"$FRAMEWORK"'/runtime/lib/load.sh" >/dev/null 2>&1
  goalspec_close_archive_active v0042
'
for f in contract.yaml contract-review-v2.yaml intake-capture-review-v2.yaml artifacts/blob.bin state.yaml; do
  [ -f "$H/v0042/$f" ] && ok "archive copied $f into history/v0042/" \
    || bad "archive dropped $f (allowlist gap regressed)"
done

# vacate_active must leave active/ with ONLY state.yaml (tombstone).
GOALSPEC_ROOT="$REPO/.goalspec" PROJECT_ROOT="$REPO" bash -c '
  . "'"$FRAMEWORK"'/runtime/lib/load.sh" >/dev/null 2>&1
  goalspec_close_vacate_active
'
left="$(find "$A" -mindepth 1 -printf '%f\n' 2>/dev/null | sort | paste -sd' ')"
if [ "$left" = "state.yaml" ]; then
  ok "vacate left only state.yaml tombstone"
else
  bad "vacate left residue beyond state.yaml: '$left'"
fi

# Bug B guard rule (inline in commands/close.sh:137): vname must be ^v[0-9]+$
# with a numeric part >= 1. Pin the exact judgment so it cannot drift.
guard_ok() { { [[ "$1" =~ ^v[0-9]+$ ]] && [ "${1#v}" -ge 1 ]; }; }
guard_ok ""        && bad "guard accepted empty"     || ok "guard rejected empty vname"
guard_ok "v0000"   && bad "guard accepted v0000"     || ok "guard rejected v0000"
guard_ok "v0001"   && ok "guard accepted v0001"      || bad "guard rejected v0001"
guard_ok "v0042"   && ok "guard accepted v0042"      || bad "guard rejected v0042"
guard_ok "v10000"  && ok "guard accepted v10000"     || bad "guard rejected v10000 (5-digit)"
guard_ok "junk"    && bad "guard accepted junk"      || ok "guard rejected junk"

[ "$TESTS_FAIL" -eq 0 ]
