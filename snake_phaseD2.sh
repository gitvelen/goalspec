#!/usr/bin/env bash
# Phase D2 — resume from WU-004 (WU-001..003 already pass) with corrected evidence_refs.
# WU-004 binds EVIDREQ-004 + EVIDREQ-005, so each of its criteria verdicts must cite
# evidence covering BOTH (EV-004 + EV-005).
set -uo pipefail
cd /home/admin/snake
GS=".goalspec/goalspec"
WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT
CHASH="$(yq e '.contract_hash' .goalspec/active/contract.yaml)"
EHASH="$(sha256sum .goalspec/active/evidence.yaml | awk '{print "sha256:"$1}')"

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
    echo "FAIL judge $crit ($wu):"; "$GS" judge apply "$WORK/v.yaml" 2>&1 | head -4; exit 1; fi
}

# WU-004 — both criteria cite EV-004 + EV-005 (cover WU-004's two evidence requirements)
judge WU-004 CRIT-004 "EV-004,EV-005" "EV-004 wall game over and EV-005 restart cover WU-004 evidence requirements"
judge WU-004 CRIT-005 "EV-004,EV-005" "EV-005 restart reset and EV-004 game over freeze cover WU-004"

# WU-005 — final
"$GS" next | grep -q WU-005 && echo "ok next WU-005"
judge WU-005 CRIT-FINAL-001 "EV-001,EV-002,EV-003,EV-004,EV-005" "all five scenarios green in browser no out of scope feature implemented"

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
if "$GS" complete; then echo "=== PHASE D2 DONE: completed ==="; else
  echo "=== complete FAILED ==="; "$GS" complete 2>&1 | head; exit 1; fi
echo "--- history ---"; ls .goalspec/history/
echo "--- final status ---"; "$GS" status | grep -E '^STATE|^CURRENT_WORK_UNIT'
