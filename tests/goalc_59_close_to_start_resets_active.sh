#!/usr/bin/env bash
# GOALC #59: close→start must reset the active workspace. A prior, closed
# change's frozen contract/criteria/goal/evidence/verdict must NOT leak into the
# next change, and the next change must get a FRESH goal id — not reuse the
# stale active_goal_id that close leaves behind in state.yaml (which made every
# change share one id and made versions.yaml ambiguous). Covers both entry
# points: `new-goal` and `start` (intake begin), which share the reset helper.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Seed artifacts mimicking a prior, closed change frozen in active/.
seed_legacy_residue() {
  local a="$REPO/.goalspec/active"
  cat > "$a/contract.yaml" <<'YML'
status: frozen
contract_hash: sha256:legacycontracthash
legacy_contract_marker: true
criteria:
  - id: CRIT-LEGACY-999
    statement: legacy
YML
  cat > "$a/criteria.yaml" <<'YML'
status: frozen
criteria:
  - id: CRIT-LEGACY-999
    title: legacy criterion
    kind: machine
YML
  cat > "$a/goal.yaml" <<'YML'
status: frozen
legacy_goal_marker: true
content: legacy goal body
YML
  cat > "$a/evidence.yaml" <<'YML'
evidence:
  - id: EV-LEGACY-1
    contract_hash: sha256:legacycontracthash
YML
  cat > "$a/verdict.yaml" <<'YML'
verdicts:
  - criteria_ref: CRIT-LEGACY-999
    verdict: pass
YML
}

# Simulate the terminal state of a fully-closed prior change: status closed AND
# recorded in versions.yaml. Real close writes both; the version record is what
# the next goal_id sequence counts from. We skip real close (no gh/git-remote).
simulate_closed() {
  local g="$1"
  yq e -i '.status = "closed"' "$REPO/.goalspec/active/state.yaml"
  mkdir -p "$REPO/.goalspec/project"
  cat > "$REPO/.goalspec/project/versions.yaml" <<YML
versions:
  - version: v0001
    goal_id: $g
    closed_at: "2026-06-22T11:25:15Z"
    contract_hash: sha256:legacycontracthash
    close_package_hash: sha256:legacyclosepackage
YML
}

# Assert active/ carries no legacy residue and contract is back to template draft.
assert_no_legacy() {
  local a="$REPO/.goalspec/active" label="$1"
  for f in contract.yaml criteria.yaml goal.yaml evidence.yaml verdict.yaml; do
    if grep -Eq "LEGACY|legacy_" "$a/$f" 2>/dev/null; then
      bad "$label: $f still carries prior-change legacy residue"
      return 1
    fi
  done
  [ "$(yq e '.status // ""' "$a/contract.yaml")" = "draft" ] \
    && ok "$label: contract.yaml reset to template draft (was frozen)" \
    || { bad "$label: contract.yaml not reset to draft"; return 1; }
}

# --- Case A: new-goal from closed ---
fresh_initialized_repo goalc-59-newgoal
"$REPO_GS" new-goal "prior" >/dev/null
g1="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
seed_legacy_residue
simulate_closed "$g1"

"$REPO_GS" new-goal "next" >/dev/null
g2="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
[ "$g2" != "$g1" ] && ok "new-goal minted a fresh goal id ($g1 -> $g2)" \
  || bad "new-goal reused stale goal id ($g1)"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "spec_drafting" ] \
  && ok "new-goal reached spec_drafting" \
  || bad "new-goal did not reach spec_drafting"
assert_no_legacy "new-goal"

# --- Case B: start (intake begin) from closed behaves the same ---
fresh_initialized_repo goalc-59-start
"$REPO_GS" new-goal "prior" >/dev/null
g1="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
seed_legacy_residue
simulate_closed "$g1"

"$REPO_GS" start "another" >/dev/null
g2="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
[ "$g2" != "$g1" ] && ok "start minted a fresh goal id ($g1 -> $g2)" \
  || bad "start reused stale goal id ($g1)"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" != "closed" ] \
  && ok "start advanced out of closed" \
  || bad "start left status closed"
assert_no_legacy "start"

[ "$TESTS_FAIL" -eq 0 ]
