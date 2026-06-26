#!/usr/bin/env bash
# GOALC #54: Self-Harness advisory candidate (Loop Engineering Self-Harness, human-
# gated). On a confirmed failure (capped/stalled) the framework emits an advisory
# harness-improvement-candidate.yaml skeleton; it never auto-applies, and close
# archives it. Promotion stays human-gated (reviewed_by_human / promoted).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

P54="$TESTS_TMP_ROOT/p54"; mkdir -p "$P54"
CAND() { echo "$REPO/.goalspec/active/harness-improvement-candidate.yaml"; }

setup_frozen() {
  fresh_initialized_repo "goalc-54-$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal >/dev/null
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  printf 'kind: contract\nresult: pass\nblocking_questions: []\nnotes: ok\n' > "$P54/c.yaml"
  "$REPO_GS" review apply "$P54/c.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  "$REPO_GS" freeze >/dev/null
}

write_ev() {
  local chash="$1"
  mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
}

apply_v() {
  local c="$1" v="$2" chash ehash
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  ehash="$(cur_evidence_hash)"
  if [ "$v" = "pass" ]; then
    cat > "$P54/v.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: $v
reason: |
  Coverage audit:
  - claim: "$c satisfied"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
  else
    cat > "$P54/v.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: $v
reason: $v-note
context: fresh
evaluated_by: master
YML
  fi
  "$REPO_GS" judge apply "$P54/v.yaml" >/dev/null
}

chash_of() { yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml"; }

# === Case 1: cap emits the advisory skeleton ===
setup_frozen cap
yq e -i '.run_loop.max_iterations = 2' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(chash_of)"
apply_v CRIT-001 fail
apply_v CRIT-FINAL-001 fail   # iteration 2 -> capped
[ "$(yq e '.run_loop.last_outcome' "$REPO/.goalspec/active/state.yaml")" = "capped" ] && ok "loop capped" || bad "not capped"
[ -f "$(CAND)" ] && ok "candidate emitted on cap" || bad "no candidate emitted"
[ "$(yq e '.status' "$(CAND)")" = "proposed" ] && ok "candidate status=proposed" || bad "candidate status not proposed"
[ "$(yq e '.failure_kind' "$(CAND)")" = "capped" ] && ok "failure_kind=capped" || bad "failure_kind not capped"
[ "$(yq e '.failure_step.iteration' "$(CAND)")" = "2" ] && ok "failure_step.iteration recorded" || bad "failure_step.iteration wrong"
yq e '.task_signature.repeatedly_failing_criteria[]' "$(CAND)" | grep -qx "CRIT-001" \
  && ok "repeatedly_failing_criteria lists CRIT-001" || bad "repeatedly_failing_criteria missing"
# rule-version provenance
[ "$(yq e '.rule_version.contract_hash' "$(CAND)")" = "$(chash_of)" ] && ok "rule_version.contract_hash matches frozen basis" || bad "contract_hash mismatch"
[ -n "$(yq e '.rule_version.prompt_hash' "$(CAND)")" ] && ok "rule_version.prompt_hash recorded" || bad "no prompt_hash"
[ -n "$(yq e '.rule_version.master_md_hash' "$(CAND)")" ] && ok "rule_version.master_md_hash recorded" || bad "no master_md_hash"
# human gate: framework never auto-promotes
[ "$(yq e '.reviewed_by_human' "$(CAND)")" = "false" ] && ok "reviewed_by_human=false (human gate)" || bad "reviewed_by_human not false"
[ "$(yq e '.promoted' "$(CAND)")" = "false" ] && ok "promoted=false (no auto-apply)" || bad "promoted not false"

# === Case 2: stall emits with failure_step from the trace ===
setup_frozen stall
yq e -i '.run_loop.stall_threshold = 2' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(chash_of)"
apply_v CRIT-001 fail
apply_v CRIT-001 fail
apply_v CRIT-001 fail   # round 3 -> stalled
[ "$(yq e '.run_loop.last_outcome' "$REPO/.goalspec/active/state.yaml")" = "stalled" ] && ok "loop stalled" || bad "not stalled"
[ "$(yq e '.failure_kind' "$(CAND)")" = "stalled" ] && ok "failure_kind=stalled" || bad "failure_kind not stalled"
[ "$(yq e '.failure_step.refused_criterion' "$(CAND)")" = "CRIT-001" ] \
  && ok "failure_step.refused_criterion from trace last entry" || bad "refused_criterion wrong"
[ -n "$(yq e '.failure_step.validator_reason' "$(CAND)")" ] && ok "failure_step.validator_reason populated from trace" || bad "validator_reason empty"

# === Case 3: idempotent — a second capped round does not overwrite ===
setup_frozen idem
yq e -i '.run_loop.max_iterations = 2' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(chash_of)"
apply_v CRIT-001 fail
apply_v CRIT-FINAL-001 fail   # cap
[ -f "$(CAND)" ] || { bad "candidate not emitted"; }
# sentinel: if a second emit attempt ran, it would reset emitted_at.
first_at="$(yq e '.emitted_at' "$(CAND)")"
# re-trigger the emit path directly (simulating a second capped round's hook).
. "$REPO/.goalspec/runtime/lib/load.sh" 2>/dev/null
GOALSPEC_ROOT="$REPO/.goalspec" PROJECT_ROOT="$REPO" goalspec_harness_emit_candidate capped 2>/dev/null
[ "$(yq e '.emitted_at' "$(CAND)")" = "$first_at" ] && ok "candidate emission is idempotent" || bad "candidate was overwritten"

# === Case 4: close archives the candidate to history ===
# Use the cap-exempt all-pass path so close can proceed despite the cap.
setup_frozen archive
yq e -i '.run_loop.max_iterations = 2' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
write_ev "$(chash_of)"
apply_v CRIT-001 pass
apply_v CRIT-FINAL-001 pass   # iteration 2 -> capped, but all pass (exempt at run)
[ -f "$(CAND)" ] && ok "candidate emitted under cap-exempt all-pass" || bad "no candidate under exempt path"
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      statement: x
      status: active
YML
"$REPO_GS" run >/dev/null 2>&1
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "ready_to_close" ] && ok "run advanced to ready_to_close under cap exemption" || bad "not ready_to_close"
vname="$(yq e '.close.history_version' "$REPO/.goalspec/active/state.yaml")"
[ -z "$vname" ] || [ "$vname" = "null" ] && vname="v0001"
"$REPO_GS" close >/dev/null 2>&1
vname="$(yq e '.close.history_version' "$REPO/.goalspec/active/state.yaml")"
[ -f "$REPO/.goalspec/history/$vname/harness-improvement-candidate.yaml" ] \
  && ok "close archives the candidate to history" || bad "candidate not archived"

# === Case 5: scope forbids a Subagent write to the candidate ===
# POST-UNTRACK LIMITATION: .goalspec/ is gitignored, so scope-check's git-diff
# can no longer see a Subagent write to .goalspec/active/harness-improvement-
# candidate.yaml, and the candidate has no frozen hash baseline. Direct writes
# are instead defended by the close archive + human promotion gate
# (reviewed_by_human / promoted) — same coverage narrowing as goalc_10 D/E/G.
setup_frozen scope
git -C "$REPO" add -A && git -C "$REPO" commit -q -m baseline-after-freeze 2>/dev/null || true
mkdir -p "$REPO/.goalspec/active"
echo "tamper" > "$REPO/.goalspec/active/harness-improvement-candidate.yaml"
if GOALSPEC_SCOPE_ROLE=subagent "$REPO_GS" scope-check >"$P54/sc.txt" 2>&1; then
  ok "Subagent candidate write no longer scope-caught (post-untrack limitation)"
else
  bad "scope-check unexpectedly caught Subagent candidate write"
fi
/bin/rm -f "$REPO/.goalspec/active/harness-improvement-candidate.yaml"

[ "$TESTS_FAIL" -eq 0 ]
