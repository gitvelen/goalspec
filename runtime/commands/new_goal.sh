#!/usr/bin/env bash
# new-goal.sh — create a new active goal.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"

sources=()
intent_parts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --source|--from-doc|--from-file|--from-dir)
      [ $# -ge 2 ] || { echo "goalspec new-goal: $1 requires a path" >&2; exit 2; }
      sources+=("$2")
      shift 2
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do intent_parts+=("$1"); shift; done
      ;;
    --*)
      echo "goalspec new-goal: unknown option $1" >&2
      exit 2
      ;;
    *)
      intent_parts+=("$1")
      shift
      ;;
  esac
done

# V2 §11: a new goal may begin only from no_goal or closed.
goalspec_assert_can_start || exit 1

# Reset the entire active workspace to clean templates for a brand-new goal
# (shared with `start`'s ensure_active_goal). Wipes any prior change's
# contract/criteria/evidence/verdict/etc. so they cannot leak into this goal.
goalspec_reset_active_workspace
goal_id="$(yq e '.active_goal_id' "$state_file")"

# If a one-line human intent was passed, drop it into the Intent section body.
if [ "${#intent_parts[@]}" -ge 1 ]; then
  intent="${intent_parts[*]}"
  gf="$GOALSPEC_ROOT/active/goal.md"
  awk -v intent="$intent" '
    BEGIN { in_intent=0; printed=0 }
    /^## 1\. Intent/ { in_intent=1; print; printf "\n%s\n", intent; printed=1; next }
    /^## / { in_intent=0 }
    {
      # Skip the empty line that originally followed the Intent header.
      if (in_intent && printed==1 && $0 ~ /^[[:space:]]*$/) { printed=2; next }
      print
    }
  ' "$gf" > "$gf.tmp" && mv "$gf.tmp" "$gf"
fi

if [ "${#sources[@]}" -gt 0 ]; then
  for src in "${sources[@]}"; do
    goalspec_intake_add_source "$src"
  done
  gf="$GOALSPEC_ROOT/active/goal.md"
  src_lines=""
  for src in "${sources[@]}"; do
    src_lines="${src_lines}  - ${src}"$'\n'
  done
  awk -v src_lines="$src_lines" '
    BEGIN { inserted=0 }
    /^## 7\. Sources and Decisions/ {
      print
      print "- sources:"
      printf "%s", src_lines
      inserted=1
      next
    }
    { print }
  ' "$gf" > "$gf.tmp" && mv "$gf.tmp" "$gf"
fi

# Record initial hashes so first edit is detected (goal_hash set when intake review applied).
yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$state_file"

echo "new active goal: $goal_id"
echo "  status: spec_drafting"
echo "  goal.md: $GOALSPEC_ROOT/active/goal.md"
echo "next: fill in active/goal.md (intake agent), then 'goalspec review prompt intake'"
