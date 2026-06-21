#!/usr/bin/env bash
# GOALC #43: V2 §6 — the close package lists the verification commands (from
#            project/profile.yaml) that final verification will run at close,
#            instead of an empty placeholder.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-43
# Configure the profile's verification commands before the close package is built.
# profile.yaml is long-term committed project config, so commit it before opening
# a goal — otherwise it reads as a dirty file relative to the goal's base revision
# and scope-check blocks the close package generation.
pf="$REPO/.goalspec/project/profile.yaml"
yq e -i '.commands.test = ["npm test", "npm run test:e2e"]' "$pf"
yq e -i '.commands.build = ["npm run build"]' "$pf"
yq e -i '.commands.lint = ["npm run lint"]' "$pf"
yq e -i '.commands.typecheck = []' "$pf"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "configure profile verification commands"

"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p43"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null

CHASH="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"
cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$CHASH"
    criteria_refs: [CRIT-001, CRIT-FINAL-001]
    evidence_requirement_refs: [EVIDREQ-001]
    command: "true"
    exit_code: 0
    artifact_paths: []
    provider_source: not_required
    runtime_boundary: browser
    persistence: memory
    completion_level: integrated_runtime
    reproducible: true
    produced_by: subagent
    produced_at: 2026-06-15T00:00:00Z
    residual_risk: {level: none, notes: ""}
YML
EHASH="$(cur_evidence_hash)"
for c in CRIT-001 CRIT-FINAL-001; do
cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$CHASH"
evidence_hash: "$EHASH"
verdict: pass
reason: ok
context: fresh
evaluated_by: master
YML
"$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
done
cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches: []
YML
"$REPO_GS" run >/dev/null

cpf="$REPO/.goalspec/active/close-package.yaml"
[ "$(yq e '.verification.commands | length' "$cpf")" = "4" ] \
  && ok "close package lists 4 verification commands" \
  || bad "verification.commands length != 4"

cmds="$(yq e '.verification.commands[].command' "$cpf")"
for want in "npm test" "npm run test:e2e" "npm run build" "npm run lint"; do
  if echo "$cmds" | grep -qxF "$want"; then
    ok "close package includes verification command: $want"
  else
    bad "close package missing verification command: $want"
  fi
done

# typecheck was empty — it must contribute no entry.
[ "$(echo "$cmds" | grep -c .)" = "4" ] \
  && ok "empty command arrays contribute no spurious entries" \
  || bad "unexpected number of verification command lines"

# Commands have not run yet at package-generation time, so exit codes are null.
[ "$(yq e '.verification.commands[].exit_code' "$cpf" | sort -u)" = "null" ] \
  && ok "verification exit codes null (run at /goalspec close)" \
  || bad "verification exit codes not null"

[ "$TESTS_FAIL" -eq 0 ]
