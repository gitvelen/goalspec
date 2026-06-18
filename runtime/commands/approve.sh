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
