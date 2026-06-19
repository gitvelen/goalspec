#!/usr/bin/env bash
# GOALC #28: `goalspec validate` collects ALL findings (no fail-fast) across
#            schema errors, staleness warnings, and (--strict) cross-file
#            reference-integrity errors. Supports --json. Exits 0 when clean,
#            1 on any error (warnings do not fail unless --strict).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Substring test that is immune to the `set -o pipefail` + `grep -q` early-exit
# / SIGPIPE trap (grep -q closing the pipe makes a matching pipeline return
# non-zero under pipefail). Capture to a var, test with case — no pipes.
contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac }

# 1. Fresh project: the placeholder contract is skipped and the goal template
#    already has its sections, so validate is clean (exit 0, no errors).
fresh_initialized_repo goalc-28-fresh
if "$REPO_GS" validate >/dev/null 2>&1; then ok "validate clean on fresh project"; else bad "validate should be clean on fresh project"; fi
out="$("$REPO_GS" validate 2>&1)"
if contains "$out" "[ERROR]"; then bad "fresh project has unexpected error"; else ok "fresh project reports no errors"; fi

# Helper: drive a repo through freeze.
to_frozen() {
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  compile_to_awaiting_confirmation
  do_freeze
}

# 2. Clean frozen lifecycle: validate --all exits 0 (completion-readiness
#    warnings are informational, not errors).
fresh_initialized_repo goalc-28-clean
to_frozen
if "$REPO_GS" validate >/dev/null 2>&1; then ok "validate --all clean at freeze"; else bad "validate should pass at freeze (warnings ok)"; fi
out="$("$REPO_GS" validate 2>&1)"
if contains "$out" "[ERROR]"; then bad "frozen lifecycle has unexpected error"; else ok "frozen lifecycle reports no errors"; fi

# 3. Broken goal.md (missing required section) -> error + exit 1.
fresh_initialized_repo goalc-28-goalbad
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
sed -i '/## 3. Success Model/d' "$REPO/.goalspec/active/goal.md"
if "$REPO_GS" validate >/dev/null 2>&1; then bad "validate should fail on broken goal"; else ok "validate fails on broken goal"; fi
out="$("$REPO_GS" validate 2>&1)"
if contains "$out" "missing section: Success Model"; then ok "reports missing Success Model section"; else bad "did not report missing section"; fi

# 4. Dangling criteria_ref: cross-file integrity is reported ONLY under --strict.
fresh_initialized_repo goalc-28-dangle
to_frozen
yq e -i '.verdicts += [{"criteria_ref":"CRIT-NOPE","verdict":"pass","context":"fresh","reason":"dangle","evaluated_by":"master"}]' "$REPO/.goalspec/active/verdict.yaml"
if "$REPO_GS" validate >/dev/null 2>&1; then ok "non-strict ignores dangling ref (exit 0)"; else bad "non-strict should ignore dangling ref"; fi
out="$("$REPO_GS" validate 2>&1)"
if contains "$out" "CRIT-NOPE"; then bad "non-strict leaked integrity finding"; else ok "non-strict hides dangling ref"; fi
if "$REPO_GS" validate --strict >/dev/null 2>&1; then bad "strict should fail on dangling ref"; else ok "strict fails on dangling ref"; fi
out="$("$REPO_GS" validate --strict 2>&1)"
if contains "$out" "criteria_ref 'CRIT-NOPE' not found"; then ok "strict reports dangling criteria_ref"; else bad "strict did not report dangling ref"; fi

# 5. collect-all: two unrelated issues both surface in one run (not fail-fast).
fresh_initialized_repo goalc-28-multi
to_frozen
sed -i '/## 3. Success Model/d' "$REPO/.goalspec/active/goal.md"
yq e -i '.verdicts += [{"criteria_ref":"CRIT-NOPE","verdict":"pass","context":"fresh","reason":"dangle","evaluated_by":"master"}]' "$REPO/.goalspec/active/verdict.yaml"
out="$("$REPO_GS" validate --strict 2>&1)"
if contains "$out" "Success Model"; then ok "collect-all surfaces goal issue"; else bad "collect-all missed goal issue"; fi
if contains "$out" "CRIT-NOPE"; then ok "collect-all surfaces integrity issue"; else bad "collect-all missed integrity issue"; fi

# 6. --json: machine-readable with ok/errors/warnings/findings; ok reflects errors.
json="$("$REPO_GS" validate --strict --json 2>/dev/null)"
[ "$(echo "$json" | yq e 'has("ok")'       -)" = "true" ] && ok "json has .ok"       || bad "json missing .ok"
[ "$(echo "$json" | yq e 'has("errors")'   -)" = "true" ] && ok "json has .errors"   || bad "json missing .errors"
[ "$(echo "$json" | yq e 'has("findings")' -)" = "true" ] && ok "json has .findings" || bad "json missing .findings"
[ "$(echo "$json" | yq e '.ok'     -)" = "false" ] && ok "json ok=false on errors" || bad "json ok should be false on errors"
[ "$(echo "$json" | yq e '.errors' -)" -ge 1 ]     && ok "json errors>=1"          || bad "json errors should be >=1"

# 6b. --json on a clean state reports ok=true.
fresh_initialized_repo goalc-28-jsonclean
to_frozen
jc="$("$REPO_GS" validate --json 2>/dev/null)"
[ "$(echo "$jc" | yq e '.ok' -)" = "true" ] && ok "json ok=true when clean" || bad "json ok should be true when clean"

# 7. Single-target: `validate contract --strict` reports the dangling ref and
#    does not drag in goal/state checks.
fresh_initialized_repo goalc-28-single
to_frozen
yq e -i '.verdicts += [{"criteria_ref":"CRIT-NOPE","verdict":"pass","context":"fresh","reason":"dangle","evaluated_by":"master"}]' "$REPO/.goalspec/active/verdict.yaml"
sout="$("$REPO_GS" validate contract --strict 2>&1)"
if contains "$sout" "CRIT-NOPE"; then ok "single-target contract --strict reports ref"; else bad "single-target missed ref"; fi
if contains "$sout" "Success Model"; then bad "single-target leaked unrelated goal check"; else ok "single-target scoped to contract only"; fi

[ "$TESTS_FAIL" -eq 0 ]
