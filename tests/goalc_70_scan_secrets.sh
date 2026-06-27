#!/usr/bin/env bash
# GOALC #70: scan_secrets at /goalspec close — keep WIDE detection (quote AND
#            bare literals, so real .env-style leaks are not missed) but stop
#            false-positiving on function-call assignments (password=env.get(),
#            must_change_password=bool(...)) and honor a path allowlist for
#            known dummy-credential paths (tests/fixtures/docs).
#            velentrade postmortem: scan blocked close on env.get()/bool() reads
#            and on hard-coded dummy test passwords.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Drive a fresh repo to ready_to_close, calling $1 to place sample files AFTER
# freeze (so the freeze dirty-worktree gate is not tripped) and BEFORE run (so
# the close-package changed_files_hash includes the sample). Mirrors
# prepare_ready_to_close but with a sample-placement hook between freeze and run.
setup_with_sample() {
  local sample_fn="$1"
  "$REPO_GS" new-goal "test" >/dev/null
  make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
  approve_intake_and_goal
  "$REPO_GS" compile >/dev/null
  make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
  local tmp="$TESTS_TMP_ROOT/ready-70-$(basename "$REPO")"
  mkdir -p "$tmp"
  cat > "$tmp/contract.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
  "$REPO_GS" review apply "$tmp/contract.yaml" >/dev/null
  "$REPO_GS" approve contract >/dev/null
  "$REPO_GS" freeze >/dev/null
  "$sample_fn"
  local chash ehash c
  chash="$(yq e '.contract_hash' "$REPO/.goalspec/active/contract.yaml")"
  cat > "$REPO/.goalspec/active/evidence.yaml" <<YML
evidence:
  - id: EV-001
    contract_hash: "$chash"
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
  ehash="$(cur_evidence_hash)"
  for c in CRIT-001 CRIT-FINAL-001; do
    cat > "$tmp/v-$c.yaml" <<YML
criteria_ref: $c
evidence_refs: [EV-001]
contract_hash: "$chash"
evidence_hash: "$ehash"
verdict: pass
reason: |
  Coverage audit:
  - claim: "minimal ready-to-close criterion"
    evidence: [EV-001]
    sufficiency: sufficient
    why: "EV-001 satisfies the test fixture evidence requirement."
  conclusion: "pass"
context: fresh
evaluated_by: master
YML
    "$REPO_GS" judge apply "$tmp/v-$c.yaml" >/dev/null
  done
  cat > "$REPO/.goalspec/active/memory-patch.yaml" <<'YML'
patches:
  - kind: capability
    content:
      id: CAP-001
      statement: x
      status: active
YML
  "$REPO_GS" run >/dev/null
}

# Run close in the current repo; assert the expected outcome. archive_only mode
# avoids any gh/remote dependency — the gate (incl. scan) still runs.
# $1=case-label  $2=expect(ok|blocked)
run_close_case() {
  local label="$1" expect="$2" rc
  "$REPO_GS" close >/tmp/goalspec-70-$label.out 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then
    [ "$expect" = "ok" ] && ok "$label: close succeeded (no false positive)" \
      || bad "$label: expected close blocked but it succeeded"
  else
    [ "$expect" = "blocked" ] && ok "$label: close blocked (secret detected)" \
      || bad "$label: expected close to succeed but it was blocked"
  fi
}

# Case 1: function-call assignment reads config, not a credential -> not flagged.
sample_func() { mkdir -p "$REPO/src"; printf 'password=os.environ.get("VELENTRADE_PSW", "BootstrapPass!2026")\n' > "$REPO/src/auth.py"; }
fresh_initialized_repo goalc-70-func
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
setup_with_sample sample_func
run_close_case func ok

# Case 2: quoted real credential literal -> detected -> blocked.
sample_quote() { mkdir -p "$REPO/src"; printf 'password="real_secret_value_12345"\n' > "$REPO/src/leak.py"; }
fresh_initialized_repo goalc-70-quote
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
setup_with_sample sample_quote
run_close_case quote blocked
grep -q 'sensitive' /tmp/goalspec-70-quote.out \
  && ok "quote: scan reports sensitive file" \
  || bad "quote: scan message missing"

# Case 3: bare literal credential (.env-style, no quotes) -> still detected.
sample_bare() { mkdir -p "$REPO/src"; printf 'DB_PASSWORD=Hunter2SuperSecretX\n' > "$REPO/src/config.env"; }
fresh_initialized_repo goalc-70-bare
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
setup_with_sample sample_bare
run_close_case bare blocked

# Case 4: dummy credential under an allowlisted path -> exempt -> succeeds.
# (Without allowlist this same literal is detected, per case 2.)
sample_allow() { mkdir -p "$REPO/src/fixtures"; printf 'password="DavePass!2026"\n' > "$REPO/src/fixtures/dummy.py"; }
fresh_initialized_repo goalc-70-allow
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
yq e -i '.delivery.scan_allow_paths = ["src/fixtures/**"]' "$REPO/.goalspec/project/profile.yaml"
setup_with_sample sample_allow
run_close_case allow ok

# Case 5: PEM private key -> detected -> blocked (other secret shapes hold).
sample_pem() { mkdir -p "$REPO/src"; printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA0Z3VS5JJcbk1dDliPm0+dummy\n-----END RSA PRIVATE KEY-----\n' > "$REPO/src/key.pem"; }
fresh_initialized_repo goalc-70-pem
yq e -i '.delivery.mode = "archive_only"' "$REPO/.goalspec/project/profile.yaml"
setup_with_sample sample_pem
run_close_case pem blocked

[ "$TESTS_FAIL" -eq 0 ]
