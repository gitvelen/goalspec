#!/usr/bin/env bash
# GOALC #25: next enforces the hard-stop caps (max_iterations /
#            max_failures_per_work_unit) before re-handing a stuck work unit —
#            the loop-engineering "hard stop" rule. Without it the loop re-enters
#            the same WU until someone notices (the Ralph Wiggum failure mode).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Fresh repo + frozen single-WU contract (WU-001 / CRIT-001), via the proven
# lib helpers (make_minimal_contract shape).
setup_frozen() {
  fresh_initialized_repo "$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  compile_to_contract_reviewed
  do_freeze
}

# Append a fresh fail verdict on CRIT-001 for WU-001, against current hashes.
apply_fail_verdict() {
  local n="$1" CHASH EHASH tmp="$TESTS_TMP_ROOT/p25"
  mkdir -p "$tmp" "$REPO/src"
  CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  echo "x$n" > "$REPO/src/a.txt"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "t$n"
    exit_code: 1
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: executor
    produced_at: "2026-06-15T00:00:0${n}Z"
    residual_risk: {level: none, notes: ""}
YML
  EHASH="$(cur_evidence_hash)"
  cat > "$tmp/vfail.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: fail
reason: "fail $n"
context: fresh
judged_by: guardian
YML
  "$REPO_GS" judge apply "$tmp/vfail.yaml" >/dev/null
}

# --- Sub-test A: consecutive-failure cap (default max_failures_per_work_unit=2) ---
setup_frozen hardstop-A

out="$("$REPO_GS" next)"
echo "$out" | /bin/grep -q 'CURRENT_WORK_UNIT: WU-001' && ok "A: next hands out WU-001 first"

apply_fail_verdict 1
out="$("$REPO_GS" next)"
if echo "$out" | /bin/grep -q 'CURRENT_WORK_UNIT: WU-001'; then
  ok "A: after 1 fail, next still returns WU-001 (1 < cap 2, not blocked)"
else
  bad "A: after 1 fail next did not return WU-001; got: $out"
fi

apply_fail_verdict 2
errA="$TESTS_TMP_ROOT/errA"
if "$REPO_GS" next 2>"$errA"; then
  bad "A: after 2 consecutive fails, next should block but exited 0"
else
  if /bin/grep -q 'consecutive non-pass' "$errA"; then
    ok "A: after 2 consecutive fails, next blocks with failure-cap message"
  else
    bad "A: blocked but wrong message: $(cat "$errA")"
  fi
fi

# --- Sub-test B: iteration cap (max_iterations=2, failures disabled) ---
setup_frozen hardstop-B
yq e -i '.max_iterations = 2' "$REPO/.goalspec/active/state.yaml"
yq e -i '.max_failures_per_work_unit = 99' "$REPO/.goalspec/active/state.yaml"

"$REPO_GS" next >/dev/null   # first hand-out (cur empty -> gate skipped), iter 0

blocked_seen=0
i=0
while [ "$i" -lt 8 ]; do
  errB="$TESTS_TMP_ROOT/errB-$i"
  if "$REPO_GS" next >/dev/null 2>"$errB"; then
    : # still re-handing the same WU
  elif /bin/grep -q 'iteration cap' "$errB"; then
    ok "B: next blocked by iteration cap after repeated re-handing (call #$i)"
    blocked_seen=1
    break
  fi
  i=$((i+1))
done
[ "$blocked_seen" -eq 1 ] || bad "B: next never hit the iteration cap"

[ "$TESTS_FAIL" -eq 0 ]
