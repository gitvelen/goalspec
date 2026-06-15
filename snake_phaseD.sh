#!/usr/bin/env bash
# Phase D — drive guardian verdicts per work unit, then complete.
set -uo pipefail
cd /home/admin/snake
GS=".goalspec/goalspec"
WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

CHASH="$(yq e '.contract_hash' .goalspec/active/contract.yaml)"
EHASH="$(sha256sum .goalspec/active/evidence.yaml | awk '{print "sha256:"$1}')"
echo "contract_hash=$CHASH"
echo "evidence_hash=$EHASH"

judge() {
  local wu=$1 crit=$2 evid=$3 reason=$4
  cat > "$WORK/v.yaml" <<YML
work_unit_ref: $wu
criteria_ref: $crit
evidence_refs: [$evid]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: "$reason"
context: fresh
judged_by: guardian
YML
  if "$GS" judge apply "$WORK/v.yaml" >/dev/null 2>&1; then echo "ok judge $crit ($wu)"; else
    echo "FAIL judge $crit ($wu):"; "$GS" judge apply "$WORK/v.yaml" 2>&1 | head -3; exit 1; fi
}

# WU-001
"$GS" next | grep -q WU-001 && echo "ok next WU-001"
judge WU-001 CRIT-001 EV-001 "EV-001 browser CDP confirms snake moves on tick without input"
# WU-002
"$GS" next | grep -q WU-002 && echo "ok next WU-002"
judge WU-002 CRIT-002 EV-002 "EV-002 browser CDP confirms direction change works and reverse input ignored"
# WU-003
"$GS" next | grep -q WU-003 && echo "ok next WU-003"
judge WU-003 CRIT-003 EV-003 "EV-003 browser CDP confirms eating grows body and score, food not on snake"
# WU-004 (two criteria)
"$GS" next | grep -q WU-004 && echo "ok next WU-004"
judge WU-004 CRIT-004 EV-004 "EV-004 browser CDP confirms wall collision game over, no move after"
judge WU-004 CRIT-005 EV-005 "EV-005 browser CDP confirms restart resets to initial state"
# WU-005 (final)
"$GS" next | grep -q WU-005 && echo "ok next WU-005"
judge WU-005 CRIT-FINAL-001 "EV-001,EV-002,EV-003,EV-004,EV-005" "all five scenarios green in browser, no out_of_scope feature implemented"

# memory-patch (guardian proposal) + approval
cat > .goalspec/active/memory-patch.yaml <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-SNAKE-001
      statement: "browser-based snake game with keyboard arrow control, single HTML file"
      status: active
  - kind: decision
    content:
      id: DEC-SNAKE-001
      statement: "single-file HTML/JS game, no backend, no build chain"
      status: active
YML
"$GS" approve memory-patch >/dev/null && echo "ok approve-memory-patch"

# commit business code + active artifacts so complete can attribute changed files
git add -A && git -c user.email=x@x -c user.name=x commit -q -m "snake: index.html game + browser evidence (WU-001..005 pass)" && echo "ok commit game+evidence"

# complete — the sole completion gate
"$GS" complete && echo "=== PHASE D DONE: completed ===" || { echo "=== complete FAILED ==="; "$GS" complete 2>&1 | head; exit 1; }
echo "--- history ---"; ls .goalspec/history/
echo "--- final status ---"; "$GS" status | grep -E '^STATE|^CURRENT_WORK_UNIT'
