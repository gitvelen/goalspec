#!/usr/bin/env bash
# sensor.sh — Tier 2 sensor verification.
# Closes the self-claim gap: a 'pass' verdict must be confirmable by re-running
# the cited evidence's command, not just by trusting the Subagent's recorded
# exit_code. Profile test/lint/typecheck only run at /goalspec close; this runs
# at judge-apply time for reproducible evidence. Side-effect safety is the
# load-bearing guard: evidence with reproducible != true is NEVER executed here.

# Verify one evidence entry by id. Returns 0 if the evidence is not reproducible
# (nothing to check) or its command exits 0 when re-run. Returns 1 and prints a
# reason to stderr if reproducible=true but the command is empty, exits non-zero,
# or (opt-in) declares coverage_claims whose routes lack a matching
# GOALSPEC_COVERED: <route> marker in the re-run output.
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
  if [ "$actual_exit" -ne 0 ]; then
    /bin/rm -f "$vout"
    echo "evidence $eid: sensor verification failed - reproducible command '$cmd' exited $actual_exit (recorded exit_code=$recorded_exit)" >&2
    return 1
  fi
  # Coverage marker check (opt-in). If the evidence declares coverage_claims,
  # the re-run output must contain a `GOALSPEC_COVERED: <route>` marker for each
  # declared route. This closes the silent-pass gap where a test runs on the
  # wrong route (e.g. an auth gate redirect) yet exits 0 because it asserted
  # generic DOM that also holds on the wrong page. The test emits the marker
  # AFTER the route-specific assertion, so a redirect fails the assertion
  # (exit != 0) before the marker is reached. Opt-in: evidence without
  # coverage_claims is unaffected (unchanged exit-0 semantics).
  cc_len="$(yq e ".evidence[] | select(.id == \"$eid\") | .coverage_claims // [] | length" "$ef" 2>/dev/null || echo 0)"
  if [ "${cc_len:-0}" -gt 0 ] 2>/dev/null; then
    ci=0; missing_markers=""
    while [ "$ci" -lt "$cc_len" ]; do
      route="$(yq e ".evidence[] | select(.id == \"$eid\") | .coverage_claims[$ci].route // \"\"" "$ef" 2>/dev/null)"
      if [ -n "$route" ] && [ "$route" != "null" ]; then
        if ! grep -qF "GOALSPEC_COVERED: $route" "$vout"; then
          missing_markers="${missing_markers}$route "
        fi
      fi
      ci=$((ci+1))
    done
    /bin/rm -f "$vout"
    if [ -n "$missing_markers" ]; then
      echo "evidence $eid: sensor coverage check failed - reproducible command exited 0 but output lacks GOALSPEC_COVERED marker for declared route(s): $missing_markers (the test likely ran on a different route than declared)" >&2
      return 1
    fi
  else
    /bin/rm -f "$vout"
  fi
  return 0
}
