#!/usr/bin/env bash
# GOALC #81: E1 — 'judge draft' emits a verdict yaml with contract_hash /
#            evidence_hash / evidence_basis_hash filled by the framework (no
#            hand-computed hashes), a valid evidence_refs array, and a reason
#            skeleton. A verdict assembled from a draft's hashes is accepted by
#            'judge apply'. Invalid crit / evidence ids are rejected at draft.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-81
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p81"; mkdir -p "$tmp"
cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"

cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
    criteria_refs: [CRIT-001]
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
  - id: EV-002
    contract_hash: "$chash"
    criteria_refs: [CRIT-001]
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

# Case A: draft emits correct hashes + refs.
"$REPO_GS" judge draft CRIT-001 --verdict pass --evidence EV-001 > "$tmp/draft.yaml" 2>"$tmp/draft.err"
if [ $? -ne 0 ]; then
  bad "E1-A: judge draft failed: $(cat "$tmp/draft.err")"
else
  d_chash="$(yq e '.contract_hash' "$tmp/draft.yaml")"
  d_basis="$(yq e '.evidence_basis_hash // ""' "$tmp/draft.yaml")"
  d_ref0="$(yq e '.evidence_refs[0]' "$tmp/draft.yaml")"
  d_verdict="$(yq e '.verdict' "$tmp/draft.yaml")"
  [ "$d_chash" = "$chash" ] && ok "E1-A1: draft contract_hash filled correctly" || bad "E1-A1: contract_hash mismatch ($d_chash vs $chash)"
  [ -n "$d_basis" ] && [ "$d_basis" != "null" ] && ok "E1-A2: draft evidence_basis_hash filled" || bad "E1-A2: evidence_basis_hash missing"
  [ "$d_ref0" = "EV-001" ] && ok "E1-A3: draft evidence_refs parsed correctly" || bad "E1-A3: evidence_refs wrong ($d_ref0)"
  [ "$d_verdict" = "pass" ] && ok "E1-A4: draft verdict echoed" || bad "E1-A4: verdict wrong ($d_verdict)"
  printf '%s\n' "$d_chash" | grep -q '^sha256:' && ok "E1-A5: hash is sha256-prefixed" || bad "E1-A5: hash format off: $d_chash"
fi

# Case B: multiple evidence ids (comma-separated) parse into a list.
"$REPO_GS" judge draft CRIT-001 --verdict pass --evidence EV-001,EV-002 > "$tmp/draft2.yaml" 2>/dev/null
n_refs="$(yq e '.evidence_refs | length' "$tmp/draft2.yaml")"
[ "$n_refs" = "2" ] && ok "E1-B: comma-separated evidence -> $n_refs refs" || bad "E1-B: expected 2 refs got '$n_refs'"

# Case C: a verdict built from draft's hashes is accepted by 'judge apply'.
cat > "$tmp/apply.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$(yq e '.contract_hash' "$tmp/draft.yaml")"
evidence_hash: "$(yq e '.evidence_hash' "$tmp/draft.yaml")"
evidence_basis_hash: "$(yq e '.evidence_basis_hash' "$tmp/draft.yaml")"
verdict: pass
reason: |-
  Coverage audit:
  - claim: "draft-derived hashes satisfy the criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 covers EVIDREQ-001; hashes came straight from 'judge draft'."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
if "$REPO_GS" judge apply "$tmp/apply.yaml" >/dev/null 2>&1; then
  ok "E1-C: draft-derived hashes accepted by judge apply"
else
  bad "E1-C: judge apply rejected draft-derived verdict"
fi

# Case D: unknown evidence id -> draft rejects.
if "$REPO_GS" judge draft CRIT-001 --verdict pass --evidence EV-999 >"$tmp/d.out" 2>"$tmp/d.err"; then
  bad "E1-D: draft accepted unknown evidence id"
else
  ok "E1-D: draft rejected unknown evidence id"
fi

# Case E: unknown criterion -> draft rejects.
if "$REPO_GS" judge draft CRIT-NOPE --verdict pass --evidence EV-001 >"$tmp/e.out" 2>"$tmp/e.err"; then
  bad "E1-E: draft accepted unknown criterion"
else
  ok "E1-E: draft rejected unknown criterion"
fi

# Case F: missing --evidence -> draft rejects with usage.
if "$REPO_GS" judge draft CRIT-001 --verdict pass >"$tmp/f.out" 2>"$tmp/f.err"; then
  bad "E1-F: draft accepted missing --evidence"
else
  ok "E1-F: draft rejected missing --evidence"
fi

[ "$TESTS_FAIL" -eq 0 ]
