#!/usr/bin/env bash
# fidelity.sh — smoke gate + Ralph Wiggum audit for /goalspec close.
#
# Velentrade postmortem (2026-06-26): 42 criteria all earned a fresh Master
# pass, yet 4 production bugs shipped. Every acceptance layer rested on
# self-reported evidence text plus an LLM judging that text — "two optimists
# blindly agreeing". A single end-to-end owner-login through real postgres
# would have surfaced all four (401/500 at each bug). This gate makes the
# most severe class of failure — claimed-done-but-core-broken — visible by
# requiring core user journeys to physically traverse invariants OUTSIDE the
# implementer's control: a real DB engine (postgres constraints, not sqlite
# create_all), a real service process, real I/O. Such a smoke test cannot be
# faked by a test helper or a sqlite fixture.
#
# Progressive (opt-in): with no smoke_tests configured, close warns but does
# not block (backward compat for projects like velentrade that have no
# profile). enforce_on_close=true makes a failing smoke test fail close. The
# Ralph audit reports whether ANY objective gate backed this close, surfacing
# the all-soft close (the actual velentrade failure mode) without any
# coverage debate — it is pure bookkeeping, not judgment.

# Read a profile field (yq expr) with a default; tolerates a missing profile.
goalspec_fidelity_profile_value() {
  local expr="$1" default="$2" pf="$GOALSPEC_ROOT/project/profile.yaml" val
  [ -f "$pf" ] || { printf '%s' "$default"; return 0; }
  val="$(yq e "$expr // \"\"" "$pf" 2>/dev/null || true)"
  if [ -z "$val" ] || [ "$val" = "null" ]; then printf '%s' "$default"; else printf '%s' "$val"; fi
}

goalspec_fidelity_enabled()          { [ "$(goalspec_fidelity_profile_value '.environment.fidelity.enabled' 'false')" = "true" ]; }
goalspec_fidelity_enforce_on_close() { [ "$(goalspec_fidelity_profile_value '.environment.fidelity.enforce_on_close' 'false')" = "true" ]; }

# Count of declared smoke tests (0 when profile or block absent).
goalspec_fidelity_smoke_count() {
  local pf="$GOALSPEC_ROOT/project/profile.yaml" n
  [ -f "$pf" ] || { printf '0'; return 0; }
  n="$(yq e '.environment.smoke_tests | length' "$pf" 2>/dev/null || echo 0)"
  printf '%s' "${n:-0}"
}

# Run smoke_tests[$idx] under its fidelity boundary: bootstrap → command
# (with env injected) → teardown (always). Echoes a failure reason and
# returns 1 on failure; silent on success. Side-effect safety: bootstrap and
# teardown only run when declared.
goalspec_fidelity_run_one() {
  local idx="$1"
  local pf="$GOALSPEC_ROOT/project/profile.yaml"
  local cmd boundary bootstrap teardown env_pairs k v
  cmd="$(yq e ".environment.smoke_tests[$idx].command // \"\"" "$pf" 2>/dev/null || true)"
  [ -n "$cmd" ] && [ "$cmd" != "null" ] || { echo "smoke[$idx]: empty command (skipped)"; return 0; }
  boundary="$(yq e ".environment.smoke_tests[$idx].fidelity // \"integration\"" "$pf" 2>/dev/null || echo integration)"
  bootstrap="$(yq e ".environment.fidelity.boundaries.$boundary.bootstrap // \"\"" "$pf" 2>/dev/null || true)"
  teardown="$(yq e ".environment.fidelity.boundaries.$boundary.teardown // \"\"" "$pf" 2>/dev/null || true)"
  # env map → KEY=VAL lines for `env`.
  env_pairs="$(yq e -o=p ".environment.fidelity.boundaries.$boundary.env // {}" "$pf" 2>/dev/null || true)"
  local env_args=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    k="${line%%=*}"; v="${line#*=}"
    [ -n "$k" ] && env_args+=("$k=$v")
  done <<<"$env_pairs"

  if [ -n "$bootstrap" ] && [ "$bootstrap" != "null" ]; then
    ( cd "$PROJECT_ROOT" && bash -lc "$bootstrap" ) >/dev/null 2>&1 \
      || { echo "smoke[$idx] ($boundary): bootstrap failed"; return 1; }
  fi
  local rc=0
  if [ "${#env_args[@]}" -gt 0 ]; then
    ( cd "$PROJECT_ROOT" && env "${env_args[@]}" bash -lc "$cmd" ) >/dev/null 2>&1 || rc=$?
  else
    ( cd "$PROJECT_ROOT" && bash -lc "$cmd" ) >/dev/null 2>&1 || rc=$?
  fi
  if [ -n "$teardown" ] && [ "$teardown" != "null" ]; then
    ( cd "$PROJECT_ROOT" && bash -lc "$teardown" ) >/dev/null 2>&1 || true
  fi
  [ "$rc" -eq 0 ] || { echo "smoke[$idx] ($boundary): command exited $rc"; return 1; }
  return 0
}

# Count pass verdicts in this close (fresh passes against the frozen contract).
goalspec_fidelity_pass_verdict_count() {
  local vf="$GOALSPEC_ROOT/active/verdict.yaml" cf="$GOALSPEC_ROOT/active/contract.yaml"
  [ -f "$vf" ] || { printf '0'; return 0; }
  local cur_chash
  cur_chash="$(goalspec_contract_hash 2>/dev/null || true)"
  # Count verdicts that are pass and whose contract_hash matches the frozen one.
  yq e "[.verdicts[] | select(.verdict == \"pass\") | select(.contract_hash == \"$cur_chash\")] | length" "$vf" 2>/dev/null || printf '0'
}

# goalspec_fidelity_gate: run smoke tests; return 0 to allow close (soft by
# default), 1 to block (only when enforce_on_close=true and a smoke failed).
# Always prints SMOKE_WARNING / RALPH_WIGGUM_WARNING to stderr when applicable
# so the all-soft close is visible even without opt-in. Echoes a one-line
# summary on stdout for the delivery record.
goalspec_fidelity_gate() {
  local n enabled enforce smoke_failures="" warnings="" gate_passed=true
  n="$(goalspec_fidelity_smoke_count)"
  enabled="$(goalspec_fidelity_enabled; echo $?)"
  enforce="$(goalspec_fidelity_enforce_on_close; echo $?)"

  if [ "${n:-0}" -eq 0 ]; then
    warnings="${warnings}SMOKE_WARNING: no end-to-end smoke test configured; core paths not verified against production invariants (M1/M5 risk). "
  else
    local i=0
    while [ "$i" -lt "$n" ]; do
      local err
      if ! err="$(goalspec_fidelity_run_one "$i")"; then
        smoke_failures="${smoke_failures}${err}; "
      fi
      i=$((i+1))
    done
    if [ -n "$smoke_failures" ]; then
      gate_passed=false
      warnings="${warnings}SMOKE_FAILURE: ${smoke_failures} "
    fi
  fi

  # Ralph Wiggum audit: was ANY objective gate present and passing? Pure
  # bookkeeping — no coverage debate. The all-soft close (velentrade) is
  # exactly objective_gate=false with N>0 pass verdicts.
  local verdicts objective_gate
  verdicts="$(goalspec_fidelity_pass_verdict_count)"
  if [ "${n:-0}" -gt 0 ] && [ "$gate_passed" = "true" ]; then
    objective_gate=true
  else
    objective_gate=false
    if [ "${verdicts:-0}" -gt 0 ]; then
      warnings="${warnings}RALPH_WIGGUM_WARNING: ${verdicts} pass verdict(s), 0 backed by an objective gate traversing production invariants — 'two optimists agreeing' failure mode. "
    fi
  fi

  # All output (warnings + summary) goes to stdout so the caller captures both
  # in one shot; exit status alone signals block-vs-warn.
  [ -z "$warnings" ] || printf '%s\n' "$warnings"
  printf 'smoke: tests=%s gate_passed=%s objective_gate=%s pass_verdicts=%s\n' \
    "${n:-0}" "$gate_passed" "$objective_gate" "${verdicts:-0}"

  # Block only when explicitly enforced AND a smoke command actually failed.
  if [ "$gate_passed" = "false" ] && goalspec_fidelity_enforce_on_close; then
    return 1
  fi
  return 0
}
