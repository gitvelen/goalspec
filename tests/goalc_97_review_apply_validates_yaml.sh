#!/usr/bin/env bash
# GOALC #97: review apply validates its input — rejects non-YAML files and
#            result values other than pass|fail — so a garbled or half-written
#            review file cannot be recorded as a passing review.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac }

fresh_initialized_repo goalc-97
"$REPO_GS" start "intent" >/dev/null
"$REPO_GS" end >/dev/null
cat > "$REPO/.goalspec/active/intake-capture.md" <<'MD'
# Intake Capture

## Goal Candidate
x
MD
tmp="$TESTS_TMP_ROOT/p97"; mkdir -p "$tmp"

# 1. non-YAML (tab indentation is illegal in YAML) -> rejected.
printf 'kind: intake-capture\n\tresult: pass\nnotes: ok\n' > "$tmp/garbled.yaml"
if "$REPO_GS" review apply "$tmp/garbled.yaml" >/dev/null 2>"$tmp/garbled.err"; then
  bad "review apply accepted non-YAML file"
else
  contains "$(<"$tmp/garbled.err")" "valid YAML" \
    && ok "review apply rejects non-YAML file" \
    || bad "review apply rejected non-YAML for wrong reason: $(head -1 "$tmp/garbled.err")"
fi

# 2. result other than pass|fail -> rejected.
cat > "$tmp/badresult.yaml" <<'YML'
kind: intake-capture
result: maybe
notes: x
YML
if "$REPO_GS" review apply "$tmp/badresult.yaml" >/dev/null 2>"$tmp/badresult.err"; then
  bad "review apply accepted invalid result"
else
  contains "$(<"$tmp/badresult.err")" "pass|fail" \
    && ok "review apply rejects result other than pass|fail" \
    || bad "review apply rejected bad result for wrong reason: $(head -1 "$tmp/badresult.err")"
fi

# 3. well-formed pass still applies (regression: validation must not reject valid input).
if stamp_intake_capture_review_pass; then
  ok "review apply still accepts a well-formed passing review"
else
  bad "review apply rejected a well-formed passing review"
fi

[ "$TESTS_FAIL" -eq 0 ]
