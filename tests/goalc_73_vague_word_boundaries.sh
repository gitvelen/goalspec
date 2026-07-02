#!/usr/bin/env bash
# GOALC #73: vague-word detection must respect ASCII word boundaries so
#            substrings like 'incorrect'(ly)/'property'/'completeness' do NOT
#            trip 'correct'/'proper'/'complete'. True positives (standalone
#            'correct', 'reasonable') still reject. CJK terms remain substring
#            matches (no reliable ERE boundary in Chinese text).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# try_freeze_with_statement <label> <statement> <expect: clean|vague>
try_freeze_with_statement() {
  local label="$1" stmt="$2" expect="$3"
  fresh_initialized_repo "goalc-73-$label"
  "$REPO_GS" new-goal "vague boundary $label" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  "$REPO_GS" compile >/dev/null
  cat > "$REPO/.goalspec/active/contract.yaml" <<YML
status: draft
goal_hash: placeholder
project_memory_hash: placeholder
contract_hash: null
criteria:
  - id: CRIT-001
    kind: machine
    statement: $stmt
    evidence_requirement_refs: [EVIDREQ-001]
  - id: CRIT-FINAL-001
    kind: machine
    final: true
    statement: final integration pass
    evidence_requirement_refs: [EVIDREQ-001]
evidence_requirements:
  - id: EVIDREQ-001
    runtime_boundary: browser
    statement: browser-level automation
constraints: []
required_regressions: []
allowed_paths: ["src/**"]
forbidden_paths: []
YML
  local tmp="$TESTS_TMP_ROOT/p73-$label"; mkdir -p "$tmp"
  cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  local frozen
  if "$REPO_GS" freeze >/dev/null 2>"$tmp/err"; then frozen=1; else frozen=0; fi
  case "$expect" in
    clean)
      if [ "$frozen" -eq 1 ]; then
        ok "no false vague flag: $label"
      elif grep -q 'vague' "$tmp/err"; then
        bad "false vague reject: $label ($stmt)"
      else
        bad "freeze failed (not vague): $label ($(head -1 "$tmp/err"))"
      fi ;;
    vague)
      if [ "$frozen" -eq 0 ] && grep -q 'vague' "$tmp/err"; then
        ok "vague correctly flagged: $label"
      else
        bad "expected vague reject: $label ($stmt) frozen=$frozen"
      fi ;;
  esac
}

# False positives the boundary fix must remove (each previously matched as a
# substring of correct/proper/complete).
try_freeze_with_statement incorrectly "the retry path handles incorrectly rejected requests" clean
try_freeze_with_statement property "property list enumerates each held asset" clean
try_freeze_with_statement completeness "the completeness check runs each night" clean

# True positives that must still reject.
try_freeze_with_statement correct "the behavior is correct" vague
try_freeze_with_statement reasonable "the outcome is reasonable" vague

[ "$TESTS_FAIL" -eq 0 ]
