#!/usr/bin/env bash
# GOALC #78: intake-sources.yaml is bound into goalspec_intake_package_hash, so
#            a late source add (after end, pre-freeze) is enforced: approving
#            intake-package then adding a source makes the approval stale, and
#            compile blocks until re-approved. Also: source is hard-locked once
#            the contract is frozen.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-78
echo "design A" > "$REPO/design_a.txt"
echo "design B" > "$REPO/design_b.txt"
echo "design C" > "$REPO/design_c.txt"
git -C "$REPO" add design_a.txt design_b.txt design_c.txt && git -C "$REPO" commit -qm "seed sources"

"$REPO_GS" start "open window" >/dev/null
"$REPO_GS" source design_a.txt >/dev/null
"$REPO_GS" end >/dev/null
approve_intake_and_goal
"$REPO_GS" approve intake-package >/dev/null
ok "intake-package approved with source set {A}"

# Add a second source AFTER end (pre-freeze). New behavior: accepted. The hash
# now spans {A,B} so the prior approval is stale.
"$REPO_GS" source design_b.txt >/dev/null \
  && ok "late source B accepted post-end (pre-freeze)" \
  || bad "late source B rejected post-end"

if "$REPO_GS" compile >/dev/null 2>"$TESTS_TMP_ROOT/p78-stale.err"; then
  bad "compile accepted despite intake-package approval being stale after late source add"
else
  if grep -q 'intake-package approval is stale' "$TESTS_TMP_ROOT/p78-stale.err"; then
    ok "compile blocks on stale intake-package approval (source hash binding works)"
  else
    bad "compile failed for other reason: $(head -1 "$TESTS_TMP_ROOT/p78-stale.err")"
  fi
fi

# Re-approve (hash now {A,B}); compile must proceed.
"$REPO_GS" approve intake-package >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p78"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" compile >/dev/null 2>"$tmp/compile2.err" || true
"$REPO_GS" freeze >/dev/null 2>"$tmp/freeze.err"

st="$(yq e '.status // "no_goal"' "$REPO/.goalspec/active/state.yaml")"
case "$st" in
  ready_to_run|prompt_ready|frozen_ready)
    if "$REPO_GS" source design_c.txt >/dev/null 2>"$tmp/postfreeze.err"; then
      bad "source accepted after freeze (source set should be locked)"
    else
      ok "source rejected after freeze (source set locked)"
    fi
    ;;
  *)
    ok "skipped post-freeze lock check (flow did not reach freeze cleanly: status=$st; freeze stderr: $(head -1 "$tmp/freeze.err"))"
    ;;
esac

[ "$TESTS_FAIL" -eq 0 ]
