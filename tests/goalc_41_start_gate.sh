#!/usr/bin/env bash
# GOALC #41: V2 §11 — /goalspec start and new-goal may begin a goal only from
#            no_goal or closed. An active (not-yet-closed) goal must be rejected,
#            never silently overwritten.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# --- spec_drafting: both start and new-goal must be rejected, state preserved ---
fresh_initialized_repo goalc-41-spec
"$REPO_GS" new-goal "first" >/dev/null
g1="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "spec_drafting" ] || bad "setup: expected spec_drafting"

if "$REPO_GS" start "second" >/dev/null 2>&1; then
  bad "start accepted while a goal is active (spec_drafting)"
else
  ok "start rejected while a goal is active (spec_drafting)"
fi
if "$REPO_GS" new-goal "second" >/dev/null 2>&1; then
  bad "new-goal accepted while a goal is active (spec_drafting)"
else
  ok "new-goal rejected while a goal is active (spec_drafting)"
fi
# A rejected start must not clobber the in-flight goal.
[ "$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")" = "$g1" ] \
  && ok "rejected start/new-goal did not replace active goal id" \
  || bad "active goal id was overwritten"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "spec_drafting" ] \
  && ok "status unchanged after rejected start" \
  || bad "status changed after rejected start"

# --- intake_collecting: a second start must be rejected, window preserved ---
fresh_initialized_repo goalc-41-intake
"$REPO_GS" start "open window" >/dev/null
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "intake_collecting" ] \
  || bad "setup: expected intake_collecting"
if "$REPO_GS" start "another" >/dev/null 2>&1; then
  bad "start accepted while intake is collecting"
else
  ok "start rejected while intake is collecting"
fi
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" = "intake_collecting" ] \
  && ok "collecting window preserved after rejected start" \
  || bad "collecting window was reset"

# --- closed: a new goal MAY start (the only non-no_goal startable state) ---
fresh_initialized_repo goalc-41-closed
"$REPO_GS" new-goal "prior" >/dev/null
g_prior="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
# Simulate the terminal state of a prior, fully-closed goal: status closed AND
# recorded in versions.yaml (real close writes both; the version record is what
# the next goal_id sequence counts from).
yq e -i '.status = "closed"' "$REPO/.goalspec/active/state.yaml"
mkdir -p "$REPO/.goalspec/project"
cat > "$REPO/.goalspec/project/versions.yaml" <<YML
versions:
  - version: v0001
    goal_id: $g_prior
    closed_at: "2026-06-22T11:25:15Z"
YML
if "$REPO_GS" new-goal "next" >/dev/null 2>&1; then
  ok "new-goal allowed from closed"
else
  bad "new-goal rejected from closed state"
fi
g_next="$(yq e '.active_goal_id' "$REPO/.goalspec/active/state.yaml")"
[ "$g_next" != "$g_prior" ] \
  && ok "new-goal minted a fresh id ($g_prior -> $g_next), not the stale one" \
  || bad "new-goal reused the stale closed goal id ($g_prior)"
[ "$(yq e '.status' "$REPO/.goalspec/active/state.yaml")" != "closed" ] \
  && ok "closed state advanced to a fresh goal" \
  || bad "still closed after new-goal"

[ "$TESTS_FAIL" -eq 0 ]
