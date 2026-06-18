#!/usr/bin/env bash
# next.sh — select next work unit (WU scheduling invariants, GOALC #11).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

cf="$GOALSPEC_ROOT/active/contract.yaml"
state_file="$GOALSPEC_ROOT/active/state.yaml"
vf="$GOALSPEC_ROOT/active/verdict.yaml"

[ -f "$cf" ] || { echo "no contract.yaml" >&2; exit 1; }
[ "$(yq e '.status' "$cf")" = "frozen" ] || { echo "next blocked: contract not frozen" >&2; exit 1; }

# Stale checks: contract change since freeze blocks next.
if goalspec_stale_contract_changed; then
  echo "next blocked: contract changed since last freeze/evidence; re-judge or re-freeze" >&2
  exit 1
fi

cur="$(yq e '.current_work_unit // ""' "$state_file")"

# Helper: latest verdict for a WU.
latest_verdict_for() {
  local wu="$1"
  [ -f "$vf" ] || { echo ""; return 0; }
  yq e "[.verdicts[] | select(.work_unit_ref == \"$wu\")] | .[-1].verdict // \"\"" "$vf"
}

# Helper: are all criteria bound to WU satisfied (pass)?
wu_criteria_all_pass() {
  local wu="$1"
  local n i crit v
  n="$(yq e ".work_units[] | select(.id == \"$wu\") | .criteria_refs | length" "$cf")"
  i=0
  while [ "$i" -lt "$n" ]; do
    crit="$(yq e ".work_units[] | select(.id == \"$wu\") | .criteria_refs[$i]" "$cf")"
    v="$(yq e "[.verdicts[] | select(.criteria_ref == \"$crit\")] | .[-1].verdict // \"\"" "$vf" 2>/dev/null)"
    [ "$v" = "pass" ] || return 1
    i=$((i+1))
  done
  return 0
}

# Helper: max trailing-consecutive non-pass verdict streak across the WU's
# bound criteria. No verdict file / no verdicts -> 0.
consecutive_failures_for_wu() {
  local wu="$1" crits c vlist v streak max=0
  [ -f "$vf" ] || { echo 0; return; }
  crits="$(yq e ".work_units[] | select(.id == \"$wu\") | .criteria_refs[]" "$cf" 2>/dev/null)"
  [ -z "$crits" ] && { echo 0; return; }
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    vlist="$(yq e "[.verdicts[] | select(.criteria_ref == \"$c\")] | .[].verdict" "$vf" 2>/dev/null)"
    [ -z "$vlist" ] && continue
    streak=0
    while IFS= read -r v; do
      if [ "$v" != "pass" ]; then streak=$((streak+1)); else streak=0; fi
    done <<<"$vlist"
    [ "$streak" -gt "$max" ] && max=$streak
  done <<<"$crits"
  echo "$max"
}

# Hard-stop gate. Echoes a reason and returns 0 (true) if a cap is exceeded —
# the caller must refuse to re-hand the WU. Returns 1 if it is safe to continue.
# Caps live in state.yaml (GOALSPEC §6): max_iterations / max_failures_per_work_unit.
hard_stop_blocked() {
  local wu="$1" max_iter max_fail iter cons
  max_iter="$(yq e '.max_iterations // 6' "$state_file")"
  max_fail="$(yq e '.max_failures_per_work_unit // 2' "$state_file")"
  iter="$(yq e '.iteration // 0' "$state_file")"
  if [ "${iter:-0}" -ge "${max_iter:-6}" ]; then
    echo "work unit $wu hit the iteration cap (iteration=$iter, max_iterations=$max_iter) without passing. Inspect .goalspec/active/trace.yaml and .goalspec/active/evidence.yaml for the root cause, or run 'goalspec reopen' if the contract/criteria/scope are wrong."
    return 0
  fi
  cons="$(consecutive_failures_for_wu "$wu")"
  if [ "${cons:-0}" -ge "${max_fail:-2}" ]; then
    echo "work unit $wu has $cons consecutive non-pass verdicts (max_failures_per_work_unit=$max_fail). Read the latest guardian verdict in .goalspec/active/verdict.yaml, fix the reported cause, or run 'goalspec reopen'."
    return 0
  fi
  return 1
}

# Decide which WU to return.
pick=""
if [ -n "$cur" ]; then
  lv="$(latest_verdict_for "$cur")"
  case "$lv" in
    fail|insufficient|blocked|stale|reopen_required|"")
      pick="$cur"
      ;;
    pass)
      if wu_criteria_all_pass "$cur"; then
        # Move to next not-yet-passed WU.
        :
      else
        pick="$cur"
      fi
      ;;
  esac
fi

if [ -z "$pick" ]; then
  # Iterate WUs in order; pick first whose criteria are not all pass and deps satisfied.
  n_wu="$(yq e '.work_units | length' "$cf")"
  i=0
  while [ "$i" -lt "$n_wu" ]; do
    wid="$(yq e ".work_units[$i].id" "$cf")"
    if ! wu_criteria_all_pass "$wid"; then
      # check deps
      ndep="$(yq e ".work_units[$i].depends_on | length" "$cf" 2>/dev/null || echo 0)"
      dep_ok=1
      j=0
      while [ "$j" -lt "$ndep" ]; do
        d="$(yq e ".work_units[$i].depends_on[$j]" "$cf")"
        if ! wu_criteria_all_pass "$d"; then dep_ok=0; break; fi
        j=$((j+1))
      done
      if [ "$dep_ok" = "1" ]; then
        pick="$wid"
        break
      fi
    fi
    i=$((i+1))
  done
fi

if [ -z "$pick" ]; then
  # All WU criteria pass — but still need final criteria pass.
  echo "next: all work units' criteria have pass verdicts; guardian must pass final criteria to complete."
  echo "next_action: goalspec judge prompt (for final criteria) -> goalspec judge apply -> goalspec complete"
  exit 0
fi

# Hard-stop gate (GOALSPEC §6). Re-handing the SAME work unit because it still
# has not passed must respect the iteration / consecutive-failure caps —
# otherwise the loop re-enters the stuck WU until someone notices
# (loop-engineering "hard stop" rule; the Ralph Wiggum failure mode).
if [ -n "$cur" ] && [ "$pick" = "$cur" ]; then
  if reason="$(hard_stop_blocked "$pick")"; then
    echo "next blocked: $reason" >&2
    exit 1
  fi
fi

# Record current WU and bump iteration if same.
if [ "$cur" = "$pick" ]; then
  iter="$(yq e '.iteration' "$state_file")"
  yq e -i ".iteration = $((iter+1))" "$state_file"
else
  yq e -i ".iteration = 0" "$state_file"
fi
yq e -i ".current_work_unit = \"$pick\"" "$state_file"
status="$(yq e '.status' "$state_file")"
if [ "$status" = "compiled" ]; then
  goalspec_state_set_status running
fi

# Print task.
goal="$(yq e ".work_units[] | select(.id == \"$pick\") | .goal" "$cf")"
allowed="$(yq e ".work_units[] | select(.id == \"$pick\") | .allowed_paths.[]" "$cf")"
forbidden="$(yq e ".work_units[] | select(.id == \"$pick\") | .forbidden_paths.[]" "$cf")"
crits="$(yq e ".work_units[] | select(.id == \"$pick\") | .criteria_refs.[]" "$cf")"
ereqs="$(yq e ".work_units[] | select(.id == \"$pick\") | .evidence_requirement_refs.[]" "$cf")"

cat <<EOF
STATE: running
NEXT_ACTION: Implement work unit $pick in allowed_paths, then provide evidence and run judge.
ROLE: executor
READ: .goalspec/ai/executor.md, .goalspec/active/contract.yaml
MAY_EDIT: $(echo "$allowed" | tr '\n' ' '), .goalspec/active/trace.yaml, .goalspec/active/evidence.yaml, .goalspec/artifacts/**
MUST_NOT_EDIT: .goalspec/active/contract.yaml, .goalspec/active/verdict.yaml, $(echo "$forbidden" | tr '\n' ' ')
BLOCKERS:
CURRENT_WORK_UNIT: $pick
COMPLETION_CONDITION: All required criteria pass; final criteria pass; no blockers; scope-check pass; memory-patch approved.

# Work unit: $pick
goal: $goal
criteria: $(echo "$crits" | tr '\n' ' ')
evidence_requirements: $(echo "$ereqs" | tr '\n' ' ')

When done: 'goalspec evidence template $pick' to scaffold evidence, then 'goalspec judge prompt $pick'
EOF
