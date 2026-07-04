#!/usr/bin/env bash
# approve.sh — record human approval binding a target hash.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

kind="${1:-}"
id="${2:-}"
case "$kind" in
  goal|contract|memory-patch|intake-capture|intake-package) target_hash_var="$kind" ;;
  high-risk)
    [ -n "$id" ] || { echo "usage: goalspec approve high-risk <id>" >&2; exit 2; }
    ;;
  regression-waiver)
    [ -n "$id" ] || { echo "usage: goalspec approve regression-waiver <id>" >&2; exit 2; }
    ;;
  *) echo "usage: goalspec approve <goal|contract|memory-patch|intake-capture|intake-package|high-risk <id>|regression-waiver <id>>" >&2; exit 2 ;;
esac

state_file="$GOALSPEC_ROOT/active/state.yaml"

# Compute current target hash for the content-bound kinds.
case "$kind" in
  goal) cur_hash="$(goalspec_goal_hash)" ;;
  contract) cur_hash="$(goalspec_contract_hash)" ;;
  memory-patch) cur_hash="$(goalspec_memory_patch_hash)" ;;
  intake-capture) cur_hash="$(goalspec_intake_capture_hash)" ;;
  intake-package) cur_hash="$(goalspec_intake_package_hash)" ;;
  high-risk|regression-waiver) cur_hash="action:$id" ;;
esac

[ -n "$cur_hash" ] || { echo "approval blocked: $kind target is missing" >&2; exit 1; }

# intake-package hard gate: a passing, fresh intake-capture review must precede
# package approval. This is the only gate that checks whether the capture
# covers what the user actually said in the conversation (the intake/contract
# reviews are fresh-context form checks and deliberately do not read the
# conversation). Without it, intent drops in intake-capture.md launder silently
# into goal.md / contract.yaml.
if [ "$kind" = "intake-package" ]; then
  rf="$GOALSPEC_ROOT/active/reviews.yaml"
  ic_pass=0
  if [ -f "$rf" ]; then
    last="$(goalspec_yq_last_match_field '[.reviews[] | select(.kind == "intake-capture")]' 'result' "$rf")"
    [ "$last" = "pass" ] && ic_pass=1
  fi
  if [ "$ic_pass" -ne 1 ]; then
    echo "approve blocked: intake-capture review has not passed. Run 'goalspec review prompt intake-capture' (hot-context; reads intake-conversation.md against intake-capture.md), resolve findings, then 'goalspec review apply <file>' with result: pass." >&2
    exit 1
  fi
  if goalspec_review_stale intake-capture; then
    echo "approve blocked: intake-capture review is stale vs current intake-capture.md (the capture changed since review). Re-run 'goalspec review prompt intake-capture' and apply a fresh pass." >&2
    exit 1
  fi
fi

# Append an approval entry. Replace any prior same-kind entry.
yq e -i "del(.approvals[] | select(.kind == \"$kind\"$( [ "$kind" = "high-risk" -o "$kind" = "regression-waiver" ] && echo " and .id == \"$id\"" )))" "$state_file"

entry="kind: \"$kind\"
target_hash: \"$cur_hash\"
approved_at: \"$(goalspec_now)\"
approved_by: \"human\""
[ -n "$id" ] && entry="$entry
id: \"$id\""

tmp="$(mktemp)"; printf '%s\n' "$entry" > "$tmp"
yq e -i ".approvals += load(\"$tmp\")" "$state_file"
/bin/rm -f "$tmp"

if [ "$kind" = "intake-capture" ]; then
  yq e -i ".intake_capture_hash = \"$cur_hash\"" "$state_file"
fi
if [ "$kind" = "intake-package" ]; then
  yq e -i ".intake_package_hash = \"$cur_hash\"" "$state_file"
fi

echo "approval recorded: kind=$kind target_hash=$cur_hash"
