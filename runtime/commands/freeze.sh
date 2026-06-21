#!/usr/bin/env bash
# freeze.sh — freeze the reviewed draft contract.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"
cf="$GOALSPEC_ROOT/active/contract.yaml"
rf="$GOALSPEC_ROOT/active/reviews.yaml"

fail() { echo "freeze blocked: $*" >&2; exit 1; }

[ -f "$cf" ] || fail "no contract.yaml"
[ "$(yq e '.status' "$cf")" = "draft" ] || fail "contract is not draft (already frozen?)"

# 1. intake review pass and fresh.
if [ ! -f "$rf" ] || [ "$(yq e '[.reviews[] | select(.kind == "intake")] | .[-1].result // ""' "$rf")" != "pass" ]; then
  fail "intake review has not passed"
fi
if goalspec_review_stale intake; then fail "intake review stale vs current goal.md"; fi

# 2. goal approval present and not stale.
if ! yq e '[.approvals[] | select(.kind == "goal")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
  fail "goal not approved"
fi
if goalspec_approval_stale goal; then fail "goal approval stale (goal.md changed since approval)"; fi

# 3. contract/criteria review pass and fresh.
if [ "$(yq e '[.reviews[] | select(.kind == "contract")] | .[-1].result // ""' "$rf")" != "pass" ]; then
  fail "contract review has not passed"
fi
if goalspec_review_stale contract; then fail "contract review stale vs current contract.yaml"; fi

# 4. contract approval present and fresh.
if ! yq e '[.approvals[] | select(.kind == "contract")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
  fail "contract not approved"
fi
if goalspec_approval_stale contract; then fail "contract approval stale (contract.yaml changed since approval)"; fi

# 5. no blocking questions.
nblock="$(yq e '[.questions[] | select(.blocking == true and .status != "resolved")] | length' "$GOALSPEC_ROOT/active/questions.yaml" 2>/dev/null || echo 0)"
[ "${nblock:-0}" -eq 0 ] || fail "unresolved blocking questions"

# 6. contract structure valid.
if ! errs="$(goalspec_schema_contract_freeze 2>&1 >/dev/null)"; then
  echo "$errs" >&2
  fail "contract schema/coverage failed"
fi

# 7. business worktree clean.
if goalspec_git_business_dirty; then
  fail "business worktree dirty; commit or stash business changes before freeze"
fi

# 7.5 reopen recovery requires an explicit, human-reviewed impact analysis.
if [ "$(yq e '.status // "no_goal"' "$state_file")" = "reopen_required" ]; then
  impact_file="$GOALSPEC_ROOT/active/reopen-impact.yaml"
  [ -f "$impact_file" ] || fail "reopen-impact.yaml missing"
  [ "$(yq e '.reviewed_by_human // false' "$impact_file")" = "true" ] || fail "reopen impact has not been reviewed by a human"
  [ -n "$(yq e '.analysis.summary // ""' "$impact_file")" ] || fail "reopen impact summary is empty"
  yq e -i '.status = "reviewed"' "$impact_file"
  yq e -i ".reviewed_at = \"$(goalspec_now)\"" "$impact_file"
  yq e -i ".reopen_impact_hash = \"$(goalspec_hash_file "$impact_file")\"" "$state_file"
fi

# 8. Inject locked regressions as required_evidence (best-effort check: warn if any
# locked regression is not reflected in required_regressions).
n_locked="$(yq e '[.regressions[] | select(.status == "locked")] | length' "$GOALSPEC_ROOT/project/regression-suite.yaml" 2>/dev/null || echo 0)"
if [ "${n_locked:-0}" -gt 0 ]; then
  echo "freeze: $n_locked locked regression(s) — verify they are reflected in contract.required_regressions"
fi

# Freeze.
chash="$(goalspec_contract_hash)"
yq e -i ".status = \"frozen\"" "$cf"
yq e -i ".contract_hash = \"$chash\"" "$cf"
# state hash + transition: frozen artifacts -> ready_to_run (enhance_v2.md §4).
yq e -i ".contract_hash = \"$chash\"" "$state_file"
yq e -i ".evidence_hash = \"$(goalspec_evidence_hash)\"" "$state_file"
# Generate the Goal-Driven Prompt -> ready_to_run.
goalspec_prompt_generate
goalspec_state_set_status ready_to_run
# Record base_revision for scope checks from here.
yq e -i ".git.base_revision = \"$(goalspec_git_head)\"" "$state_file"

echo "contract frozen. contract_hash=$chash"
echo "goal-driven prompt ready: .goalspec/active/goal-driven-prompt.md"
echo "next: run 'goalspec run' to begin implementation"
