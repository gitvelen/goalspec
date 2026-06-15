#!/usr/bin/env bash
# tests/smoke.sh — full positive lifecycle in a temp git repo.
set -uo pipefail

FRAMEWORK=/home/admin/.goalspec
TMP="${TMPDIR:-/tmp}/goalspec-smoke-$$"
trap '/bin/rm -rf "$TMP" "$WORK"' EXIT

mkdir -p "$TMP"
cd "$TMP"
git init -q
git config user.email x@x
git config user.name x

GS="$TMP/.goalspec/goalspec"
WORK="$(mktemp -d)"   # scratch dir for review/verdict payloads (must NOT pollute the business tree)

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. init
"$FRAMEWORK/goalspec" init >/dev/null || fail init
# Re-source the local copy from now on so GOALSPEC_ROOT points here.
# Commit a clean business baseline (only the goalspec framework + AGENTS/CLAUDE).
git add -A && git commit -q -m baseline || true
[ -x "$GS" ] || fail "goalspec not executable"
[ -d "$TMP/.goalspec/runtime" ] || fail "runtime missing"
[ -d "$TMP/.goalspec/ai" ] || fail "ai missing"
[ -d "$TMP/.goalspec/project" ] || fail "project missing"
[ -d "$TMP/.goalspec/active" ] || fail "active missing"
[ -f "$TMP/AGENTS.md" ] || fail "AGENTS.md missing"
[ -f "$TMP/CLAUDE.md" ] || fail "CLAUDE.md missing"
ok init

# 2. status
"$GS" status | /bin/grep -q NEXT_ACTION || fail status
ok status

# 3. new-goal
"$GS" new-goal "snake game" >/dev/null || fail new-goal
ok new-goal

# 4. fill goal.md
cat > "$TMP/.goalspec/active/goal.md" <<'MD'
# Goal

## 1. Intent
Build a snake game.

## 2. Narrative
Player loads page, snake moves, eats food, dies on wall.

## 3. Success Model
- user_visible_success: arrow keys move snake
- system_observable_success: state updates
- must_not_happen: reverse
- minimum_acceptable_result: keyboard only
- final_completion_signal: all scenarios pass

## 4. Scope
- in_scope: game loop
- out_of_scope: backend

## 5. Risk Scan
- scope-boundary: frontend only
- actor-permission: none
- data-lifecycle: memory
- failure-degradation: game over
- non-functional-baseline: 60fps
- integration-boundary: none

## 6. Goal Constraints
no backend

## 7. Sources and Decisions
- sources: human
- confirmed_decisions: html
- assumptions: desktop

## 8. Open Questions

## 9. Reopen Triggers
MD

# 5. intake review
cat > "$WORK/intake.yaml" <<'YML'
kind: intake
result: pass
blocking_questions: []
notes: ok
YML
"$GS" review apply "$WORK/intake.yaml" >/dev/null || fail intake
ok intake-review

# 6. approve goal
"$GS" approve goal >/dev/null || fail approve-goal
ok approve-goal

# 7. compile
"$GS" compile >/dev/null || fail compile
ok compile

# 8. write contract
cat > "$TMP/.goalspec/active/contract.yaml" <<'YML'
status: draft
goal_hash: dummy
project_memory_hash: dummy
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    priority: P0
    required_for_completion: true
    statement: page loads with snake moving on tick
    pass_signals: ["snake moves"]
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    priority: P0
    required_for_completion: true
    final: true
    statement: all scenarios pass in browser
    pass_signals: ["green"]
    evidence_requirement_refs: [EVIDREQ-001]
work_units:
  - id: WU-001
    goal: snake moves
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    allowed_paths: ["index.html"]
    forbidden_paths: [".goalspec/project/**", ".goalspec/active/contract.yaml"]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser automation
coverage_map:
  - goal_ref: goal.md#narrative
    criteria_refs: [CRIT-001]
constraints: []
required_regressions: []
allowed_paths: ["index.html"]
forbidden_paths: []
YML

# 9. contract review
cat > "$WORK/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$GS" review apply "$WORK/contract.yaml" >/dev/null || fail contract-review
ok contract-review

# 10. approve contract
"$GS" approve contract >/dev/null || fail approve-contract
ok approve-contract

# 11. freeze
"$GS" freeze >/dev/null || fail freeze
ok freeze

# 12. next
"$GS" next | /bin/grep -q "WU-001" || fail next
ok next

# 12a. status reports all nine required fields (GOALC #21)
for fld in STATE NEXT_ACTION ROLE READ MAY_EDIT MUST_NOT_EDIT BLOCKERS CURRENT_WORK_UNIT COMPLETION_CONDITION; do
  "$GS" status | /bin/grep -q "^${fld}:" || fail "status missing $fld"
done
"$GS" status --json | yq e '.state' - >/dev/null || fail "status --json broken"
ok status-fields

# 13. produce evidence (simulated browser automation)
cat > "$TMP/index.html" <<'HTML'
<!doctype html><html><body>snake</body></html>
HTML
git -C "$TMP" add -A && git -C "$TMP" commit -q -m init

CHASH="$("$GS" version >/dev/null; yq e '.contract_hash' "$TMP/.goalspec/active/contract.yaml")"
# Compute proper hashes via the lib
EHASH="$(sha256sum "$TMP/.goalspec/active/evidence.yaml" | awk '{print "sha256:"$1}')"

# append evidence
cat > "$TMP/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    work_unit_ref: WU-001
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "browser-automation"
    exit_code: 0
    artifact_paths: [".goalspec/artifacts/EV-001.txt"]
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: executor
    produced_at: 2026-06-15T00:00:00Z
    residual_risk:
      level: none
      notes: ""
YML
mkdir -p "$TMP/.goalspec/artifacts"
echo "passed" > "$TMP/.goalspec/artifacts/EV-001.txt"

# refresh evidence hash after the write
EHASH="$(sha256sum "$TMP/.goalspec/active/evidence.yaml" | awk '{print "sha256:"$1}')"

# 13a. scope-check passes: index.html is within WU-001 allowed_paths, but WU-001
# has no pass verdict yet — so attribution will fail here. Apply after judge pass.
# We instead verify scope-check works after judge pass below.

# 14. judge apply for CRIT-001
cat > "$WORK/verdict-001.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: "EV-001 browser automation confirms snake moves on tick"
context: fresh
judged_by: guardian
YML
"$GS" judge apply "$WORK/verdict-001.yaml" >/dev/null || fail judge-001
ok judge-001

# 14a. scope-check (executor view): the guardian's verdict.yaml write is
# allowed (judge apply protocol); business code (index.html) is within WU-001
# allowed_paths and WU-001 has a pass verdict — so an explicit executor scope
# check would still flag the post-judge verdict.yaml. We instead rely on
# `complete` running scope-check in 'system' role internally. Verify here that
# executor-side scope-check catches a NEW business file outside any WU scope:
echo "x" > "$TMP/sneaky.txt"
if "$GS" scope-check >/dev/null 2>&1; then
  fail "scope-check should reject unattributed sneaky.txt"
fi
/bin/rm -f "$TMP/sneaky.txt"
ok scope-check-rejects-unattributed

# 15. judge apply for final criteria (CRIT-FINAL-001) — WU-001 also references EVIDREQ-001? Use WU-001
cat > "$WORK/verdict-final.yaml" <<YML
work_unit_ref: WU-001
criteria_ref: CRIT-FINAL-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: "EV-001 covers all scenarios in browser"
context: fresh
judged_by: guardian
YML
# final criteria isn't bound to a WU; judge by WU-001's evidence reqs (EVIDREQ-001) which EV-001 satisfies.
"$GS" judge apply "$WORK/verdict-final.yaml" >/dev/null || fail judge-final
ok judge-final

# 16. memory-patch (guardian proposal)
cat > "$TMP/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-SNAKE-001
      statement: browser snake game
      status: active
  - kind: decision
    content:
      id: DEC-SNAKE-001
      statement: single HTML file
      status: active
YML
"$GS" approve memory-patch >/dev/null || fail approve-memory-patch
ok approve-memory-patch

# 17. complete
"$GS" complete || fail complete
ok complete

# 18. history archived
[ -d "$TMP/.goalspec/history/v0001" ] || fail history
[ -f "$TMP/.goalspec/history/v0001/summary.yaml" ] || fail summary
ok history-archived

echo "SMOKE: all green"
