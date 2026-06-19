#!/usr/bin/env bash
# GOALC #37: a verdict with evaluated_by != master (e.g. subagent) must be
#            rejected — the Subagent cannot produce a final success verdict
#            (enhance.md §12). Only evaluated_by: master is accepted at both
#            `judge apply` (hard gate) and `validate verdict` (reporting).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-37
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
compile_to_awaiting_confirmation
do_freeze

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"

# One piece of evidence bound to CRIT-001 (produced_by: subagent is fine).
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: t
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
EHASH="$(cur_evidence_hash)"
tmp="$TESTS_TMP_ROOT/p37"; mkdir -p "$tmp"

# 1. evaluated_by: subagent -> rejected (hard gate at judge apply).
cat > "$tmp/v-sub.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
evaluated_by: subagent
YML
if "$REPO_GS" judge apply "$tmp/v-sub.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted evaluated_by: subagent"
else
  ok "judge apply rejected evaluated_by: subagent"
fi

# 2. evaluated_by missing -> rejected.
cat > "$tmp/v-missing.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
YML
if "$REPO_GS" judge apply "$tmp/v-missing.yaml" >/dev/null 2>&1; then
  bad "judge apply accepted verdict missing evaluated_by"
else
  ok "judge apply rejected verdict missing evaluated_by"
fi

# 3. evaluated_by: master -> accepted.
cat > "$tmp/v-master.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/v-master.yaml" >/dev/null 2>&1; then
  ok "judge apply accepted evaluated_by: master"
else
  bad "judge apply rejected evaluated_by: master"
fi

# 4. `goalspec validate verdict` flags a subagent-authored entry already in
#    verdict.yaml (defense-in-depth reporting path).
cat > "$REPO/.goalspec/active/verdict.yaml" <<YML
verdicts:
  - criteria_ref: CRIT-001
    verdict: pass
    contract_hash: "$CHASH"
    evidence_hash: "$EHASH"
    context: fresh
    reason: forged
    evaluated_by: subagent
YML
out="$({ "$REPO_GS" validate verdict; } 2>&1 || true)"
if printf '%s\n' "$out" | grep -q "evaluated_by must be 'master'"; then
  ok "validate verdict flags evaluated_by: subagent"
else
  bad "validate verdict did not flag evaluated_by: subagent"
fi

[ "$TESTS_FAIL" -eq 0 ]
