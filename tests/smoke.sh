#!/usr/bin/env bash
# tests/smoke.sh — full positive lifecycle in a temp git repo.
set -uo pipefail

FRAMEWORK="${FRAMEWORK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP="${TMPDIR:-/tmp}/goalspec-smoke-$$"
trap '/bin/rm -rf "$TMP" "$WORK" "$SMOKE_REMOTE"' EXIT

mkdir -p "$TMP"
cd "$TMP"
git init -q
git config user.email x@x
git config user.name x

GS="$TMP/.goalspec/goalspec"
WORK="$(mktemp -d)"   # scratch dir for review/verdict payloads (must NOT pollute the business tree)

install_fake_gh() {
  local bindir
  bindir="$(mktemp -d)"
  cat > "$bindir/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr create") echo "https://example.test/org/repo/pull/1"; exit 0 ;;
esac
echo "fake gh: unsupported $*" >&2
exit 1
SH
  chmod +x "$bindir/gh"
  export PATH="$bindir:$PATH"
}

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. init
"$FRAMEWORK/goalspec" init >/dev/null || fail init
# Re-source the local copy from now on so GOALSPEC_ROOT points here.
# Commit a clean business baseline (only the goalspec framework + AGENTS/CLAUDE).
git add -A && git commit -q -m baseline || true
SMOKE_REMOTE="$(mktemp -d)/remote.git"
git init -q --bare "$SMOKE_REMOTE"
git remote add origin "$SMOKE_REMOTE"
git push -u origin main >/dev/null 2>&1 || git push -u origin master >/dev/null 2>&1 || true
install_fake_gh
[ -x "$GS" ] || fail "goalspec not executable"
[ -d "$TMP/.goalspec/runtime" ] || fail "runtime missing"
[ -d "$TMP/.goalspec/ai" ] || fail "ai missing"
[ -d "$TMP/.goalspec/project" ] || fail "project missing"
[ -d "$TMP/.goalspec/active" ] || fail "active missing"
[ -f "$TMP/AGENTS.md" ] || fail "AGENTS.md missing"
[ -f "$TMP/CLAUDE.md" ] || fail "CLAUDE.md missing"
ok init

# 2. status
"$GS" status | /bin/grep -q NEXT_USER_ACTION || fail status
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
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser automation
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

# 12a. status reports goal-driven fields (GOALC #21)
for fld in STATE GOAL FROZEN PROMPT_READY RUN_ALLOWED CLOSE_READY NEEDS_HUMAN_CONFIRMATION BLOCKERS CLOSE_BLOCKERS UNMET_CRITERIA NEXT_USER_ACTION; do
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
    criteria_refs: [CRIT-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: [".goalspec/artifacts/EV-001.txt"]
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk:
      level: none
      notes: ""
YML
mkdir -p "$TMP/.goalspec/artifacts"
echo "passed" > "$TMP/.goalspec/artifacts/EV-001.txt"

# refresh evidence hash after the write
EHASH="$(sha256sum "$TMP/.goalspec/active/evidence.yaml" | awk '{print "sha256:"$1}')"

# 13a. (scope-check attribution is verified via the sneaky.txt rejection in 14a.)

# 14. judge apply for CRIT-001
cat > "$WORK/verdict-001.yaml" <<YML
criteria_ref: CRIT-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "snake moves on tick"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 is browser automation for the smoke scenario."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
"$GS" judge apply "$WORK/verdict-001.yaml" >/dev/null || fail judge-001
ok judge-001

# 14a. scope-check (subagent view): a NEW business file outside contract
# allowed_paths must be rejected.
echo "x" > "$TMP/sneaky.txt"
if "$GS" scope-check >/dev/null 2>&1; then
  fail "scope-check should reject unattributed sneaky.txt"
fi
/bin/rm -f "$TMP/sneaky.txt"
ok scope-check-rejects-unattributed

# 15. judge apply for final criteria (CRIT-FINAL-001). Its
# evidence_requirement_refs are [EVIDREQ-001], which EV-001 satisfies.
cat > "$WORK/verdict-final.yaml" <<YML
criteria_ref: CRIT-FINAL-001
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: |
  Coverage audit:
  - claim: "all final smoke scenarios"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 covers the browser smoke scenario required by the final criterion."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
"$GS" judge apply "$WORK/verdict-final.yaml" >/dev/null || fail judge-final
ok judge-final

# 16. memory-patch (Master proposal)
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

# 17. run generates close package, then close delivers
"$GS" run >/dev/null || fail run-close-package
[ "$(yq e '.status' "$TMP/.goalspec/active/state.yaml")" = "ready_to_close" ] || fail ready-to-close
ok close-package
"$GS" close >/dev/null || fail close
ok close

# 18. history archived
[ -d "$TMP/.goalspec/history/v0001" ] || fail history
[ -f "$TMP/.goalspec/history/v0001/summary.yaml" ] || fail summary
[ -f "$TMP/.goalspec/history/v0001/delivery.yaml" ] || fail delivery
[ "$(yq e '.status' "$TMP/.goalspec/active/state.yaml")" = "closed" ] || fail closed-state
ok history-archived

echo "SMOKE: all green"
