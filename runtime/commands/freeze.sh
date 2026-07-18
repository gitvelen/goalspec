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
if [ ! -f "$rf" ] || [ "$(goalspec_yq_last_match_field '[.reviews[] | select(.kind == "intake")]' 'result' "$rf")" != "pass" ]; then
  fail "intake review has not passed"
fi
if goalspec_review_stale intake; then fail "intake review stale vs current goal.md"; fi

# 2. goal approval present and not stale.
if ! yq e '[.approvals[] | select(.kind == "goal")] | length' "$state_file" 2>/dev/null | grep -q '^[1-9]'; then
  fail "goal not approved"
fi
if goalspec_approval_stale goal; then fail "goal approval stale (goal.md changed since approval)"; fi

# 3. contract/criteria review pass and fresh.
if [ "$(goalspec_yq_last_match_field '[.reviews[] | select(.kind == "contract")]' 'result' "$rf")" != "pass" ]; then
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

# 7. business worktree clean (uncommitted changes only). Committed work since
# the last freeze's base_revision is legitimate run-loop progress and must NOT
# block re-freeze after a reopen — that was the "dirty trap" that forced users
# to hand-edit state.yaml. close (changed_files list) and scope_check still
# track base_revision..HEAD for their own, different purposes. freeze is not a
# correctness gate; "all work verdict-verified" is owned by ready_to_close via
# goalspec_close_readiness_blockers, not by this gate.
if ! goalspec_git_worktree_clean; then
  _dirty=""
  while IFS= read -r _f; do
    [ -z "$_f" ] && continue
    goalspec_git_is_framework_file "$_f" && continue
    _dirty="${_dirty}${_f} "
  done < <(
    git -C "$PROJECT_ROOT" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null
  )
  fail "business worktree has uncommitted changes relative to HEAD: ${_dirty:-<unlisted>}; commit, stash, or add to .gitignore as appropriate"
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

# Advisory (non-blocking): estimate single-run closure difficulty from the
# evidence/criteria mix. The real driver of "single run blew the context budget"
# is the share of runtime/部署-dependent evidence (browser/api/integration/db)
# and judgment-kind criteria — not the raw criteria count. Surface it at freeze
# so the human can split the goal or plan staged deployment BEFORE the run burns
# tokens discovering it. Does not block freeze.
_total_req="$(yq e '[.evidence_requirements[]] | length' "$cf" 2>/dev/null || echo 0)"
_runtime_req="$(yq e '[.evidence_requirements[] | select(.runtime_boundary == "browser" or .runtime_boundary == "api" or .runtime_boundary == "integration" or .runtime_boundary == "db")] | length' "$cf" 2>/dev/null || echo 0)"
_total_crit="$(yq e '[.criteria[]] | length' "$cf" 2>/dev/null || echo 0)"
_judgment_crit="$(yq e '[.criteria[] | select(.kind == "judgment")] | length' "$cf" 2>/dev/null || echo 0)"
if [ "${_total_req:-0}" -gt 0 ] && [ "$(( _runtime_req * 100 / _total_req ))" -ge 50 ]; then
  echo "BUDGET_WARNING: ${_runtime_req}/${_total_req} evidence_requirement 依赖 runtime (browser/api/integration/db)，${_judgment_crit}/${_total_crit} criteria 为 judgment-kind — 单 run 大概率 context 见底；建议按 goal.md ### Workunit 拆 goal 或分批部署（advisory，不阻塞 freeze）"
elif [ "${_total_crit:-0}" -gt 0 ] && [ "$(( _judgment_crit * 100 / _total_crit ))" -ge 40 ]; then
  echo "BUDGET_WARNING: ${_judgment_crit}/${_total_crit} criteria 为 judgment-kind — 单 run 难闭环（需人类/Master 裁决）；建议拆 goal（advisory，不阻塞 freeze）"
fi
if [ "${_runtime_req:-0}" -eq 0 ] && [ "${_total_req:-0}" -gt 0 ] \
  && grep -qE '用户|页面|浏览器|交互|UI|登录|click|界面|渲染|page|browser|user' "$GOALSPEC_ROOT/active/goal.md" 2>/dev/null; then
  echo "RUNTIME_EVIDENCE_WARNING: 0 runtime-boundary evidence_requirement 但 goal 含用户可见行为 — silent-pass 风险；建议至少一条 browser/integration evidence（advisory，不阻塞 freeze）"
fi

# Freeze.
chash="$(goalspec_contract_hash)"
shash="$(goalspec_scope_hash)"
yq e -i ".status = \"frozen\"" "$cf"
yq e -i ".contract_hash = \"$chash\"" "$cf"
# state hash + transition: frozen artifacts -> ready_to_run (enhance_v2.md §4).
yq e -i ".contract_hash = \"$chash\"" "$state_file"
yq e -i ".scope_hash = \"$shash\"" "$state_file"
yq e -i ".evidence_hash = \"$(goalspec_evidence_hash)\"" "$state_file"
# Generate the Goal-Driven Prompt -> ready_to_run.
goalspec_prompt_generate
goalspec_state_set_status ready_to_run
# Record base_revision for scope checks from here.
yq e -i ".git.base_revision = \"$(goalspec_git_head)\"" "$state_file"

echo "contract frozen. contract_hash=$chash"
echo "goal-driven prompt ready: .goalspec/active/goal-driven-prompt.md"
echo "next: run 'goalspec run' to begin implementation"
