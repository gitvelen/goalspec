#!/usr/bin/env bash
# GOALC #80: V1 — next_history_version infers from history/ when versions.yaml
#            is missing, instead of silently resetting to v0001 and breaking
#            archive continuity. Warns when inference happens; silent when
#            versions.yaml is authoritative or on a genuine first close.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Call the lib function directly under a chosen GOALSPEC_ROOT so the test does
# not depend on the full close flow. load.sh honors a pre-set GOALSPEC_ROOT.
run_version() {
  GOALSPEC_ROOT="$REPO/.goalspec" PROJECT_ROOT="$REPO" \
    bash -c '
      . "'"$FRAMEWORK"'/runtime/lib/load.sh" >/dev/null 2>&1
      goalspec_close_next_history_version
    ' 2>&1
}

fresh_initialized_repo goalc-80

# Case A: versions.yaml missing, history has v0001..v0003 -> v0004 + warning
rm -f "$REPO/.goalspec/project/versions.yaml"
mkdir -p "$REPO/.goalspec/history/v0001" "$REPO/.goalspec/history/v0002" "$REPO/.goalspec/history/v0003"
outA="$(run_version)"; vA="$(printf '%s\n' "$outA" | tail -1)"
if [ "$vA" = "v0004" ]; then ok "V1-A: inferred v0004 from history/"; else bad "V1-A: expected v0004 got '$vA' out=$outA"; fi
if printf '%s\n' "$outA" | grep -q "version-inference"; then ok "V1-A: inference warning emitted"; else bad "V1-A: no warning"; fi

# Case B: versions.yaml present with 2 entries -> v0003 (length+1, unchanged path), no warning
cat > "$REPO/.goalspec/project/versions.yaml" <<'YML'
versions:
  - version: v0001
    goal_id: G1
  - version: v0002
    goal_id: G2
YML
rm -rf "$REPO/.goalspec/history"
outB="$(run_version)"; vB="$(printf '%s\n' "$outB" | tail -1)"
if [ "$vB" = "v0003" ]; then ok "V1-B: versions.yaml present -> v0003 (unchanged length+1 path)"; else bad "V1-B: expected v0003 got '$vB' out=$outB"; fi
if printf '%s\n' "$outB" | grep -q "version-inference"; then bad "V1-B: should not warn when versions.yaml present"; else ok "V1-B: no warning when versions.yaml present"; fi

# Case C: both missing (genuine first close) -> v0001, NO warning (not a silent reset)
rm -f "$REPO/.goalspec/project/versions.yaml"
rm -rf "$REPO/.goalspec/history"
outC="$(run_version)"; vC="$(printf '%s\n' "$outC" | tail -1)"
if [ "$vC" = "v0001" ]; then ok "V1-C: genuine first close -> v0001"; else bad "V1-C: expected v0001 got '$vC' out=$outC"; fi
if printf '%s\n' "$outC" | grep -q "version-inference"; then bad "V1-C: should not warn on genuine first"; else ok "V1-C: no warning on genuine first"; fi

# Case D: history has non-vNNNN junk dirs -> ignored, inferred from numeric max only
mkdir -p "$REPO/.goalspec/history/v0002" "$REPO/.goalspec/history/junk" "$REPO/.goalspec/history/v_abnormal"
outD="$(run_version)"; vD="$(printf '%s\n' "$outD" | tail -1)"
if [ "$vD" = "v0003" ]; then ok "V1-D: non-numeric history dirs ignored -> v0003"; else bad "V1-D: expected v0003 got '$vD' out=$outD"; fi

# Case E: history has v0008 (first version whose number contains the octal-trap
# digit 8). Regression for the $((max_n+1)) octal bug where max_n="0008" aborted
# version inference and yielded an empty vname. Must now infer v0009 cleanly.
rm -f "$REPO/.goalspec/project/versions.yaml"
rm -rf "$REPO/.goalspec/history"
mkdir -p "$REPO/.goalspec/history/v0008"
outE="$(run_version)"; vE="$(printf '%s\n' "$outE" | tail -1)"
if [ "$vE" = "v0009" ]; then ok "V1-E: v0008 (octal-trap digit) -> v0009"; else bad "V1-E: expected v0009 got '$vE' out=$outE"; fi
if printf '%s\n' "$outE" | grep -q "value too great for base"; then bad "V1-E: octal error leaked to stderr"; else ok "V1-E: no octal error"; fi

# Case F: history has v0010. Bash parses the leading-zero 0010 as octal 8, so the
# unfixed $((max_n+1)) would silently yield v0009 (wrong value, no error). With
# the 10# fix this must yield v0011 — covers the "miscomputes without erroring"
# branch that a format-only guard cannot catch.
rm -rf "$REPO/.goalspec/history"
mkdir -p "$REPO/.goalspec/history/v0010"
outF="$(run_version)"; vF="$(printf '%s\n' "$outF" | tail -1)"
if [ "$vF" = "v0011" ]; then ok "V1-F: v0010 -> v0011 (not the octal-miscomputed v0009)"; else bad "V1-F: expected v0011 got '$vF' out=$outF"; fi

[ "$TESTS_FAIL" -eq 0 ]
