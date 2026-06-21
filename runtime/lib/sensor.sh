#!/usr/bin/env bash
# sensor.sh — Tier 2 sensor verification.
# Closes the self-claim gap: a 'pass' verdict must be confirmable by re-running
# the cited evidence's command, not just by trusting the Subagent's recorded
# exit_code. Profile test/lint/typecheck only run at /goalspec close; this runs
# at judge-apply time for reproducible evidence. Side-effect safety is the
# load-bearing guard: evidence with reproducible != true is NEVER executed here.

# Verify one evidence entry by id. Returns 0 if the evidence is not reproducible
# (nothing to check) or its command exits 0 when re-run. Returns 1 and prints a
# reason to stderr if reproducible=true but the command is empty or exits non-zero.
# args: <evidence_id>
goalspec_sensor_verify_evidence() {
  local eid="$1" ef="$GOALSPEC_ROOT/active/evidence.yaml"
  local repro cmd recorded_exit actual_exit vout
  repro="$(yq e ".evidence[] | select(.id == \"$eid\") | .reproducible // false" "$ef")"
  [ "$repro" = "true" ] || return 0
  cmd="$(yq e ".evidence[] | select(.id == \"$eid\") | .command // \"\"" "$ef")"
  if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
    echo "evidence $eid: reproducible=true but command is empty" >&2
    return 1
  fi
  recorded_exit="$(yq e ".evidence[] | select(.id == \"$eid\") | .exit_code // null" "$ef")"
  vout="$(mktemp)"
  ( cd "$PROJECT_ROOT" && bash -lc "$cmd" ) >"$vout" 2>&1; actual_exit=$?
  /bin/rm -f "$vout"
  if [ "$actual_exit" -ne 0 ]; then
    echo "evidence $eid: sensor verification failed - reproducible command '$cmd' exited $actual_exit (recorded exit_code=$recorded_exit)" >&2
    return 1
  fi
  return 0
}
