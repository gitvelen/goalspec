#!/usr/bin/env bash
# new-goal.sh — create a new active goal.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/load.sh"

state_file="$GOALSPEC_ROOT/active/state.yaml"

# Block if there's already an active, not-completed goal.
if [ -f "$state_file" ]; then
  cur_status="$(yq e '.status' "$state_file")"
  if [ "$cur_status" != "completed" ] && [ -n "$(yq e '.active_goal_id // ""' "$state_file")" ]; then
    echo "goalspec new-goal: an active goal already exists (status=$cur_status). Complete or reopen it first." >&2
    exit 1
  fi
fi

goal_id="$(goalspec_new_goal_id)"

# Reset active state and goal.md from templates.
cp "$GOALSPEC_ROOT/runtime/templates/active/state.yaml" "$state_file"
yq e -i ".active_goal_id = \"$goal_id\"" "$state_file"
yq e -i ".status = \"draft\"" "$state_file"
yq e -i ".git.base_revision = \"$(goalspec_git_head)\"" "$state_file"
yq e -i ".git.current_revision = \"$(goalspec_git_head)\"" "$state_file"

# Reset goal.md from template (only if it doesn't already have intent).
if [ ! -f "$GOALSPEC_ROOT/active/goal.md" ] || ! grep -q "## 1. Intent" "$GOALSPEC_ROOT/active/goal.md" 2>/dev/null; then
  cp "$GOALSPEC_ROOT/runtime/templates/active/goal.md" "$GOALSPEC_ROOT/active/goal.md"
fi

# If a one-line human intent was passed, drop it into the Intent section body.
if [ $# -ge 1 ] && [ -n "$1" ]; then
  intent="$*"
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

# Record initial hashes so first edit is detected (goal_hash set when intake review applied).
yq e -i ".goal_hash = \"$(goalspec_goal_hash)\"" "$state_file"

echo "new active goal: $goal_id"
echo "  status: draft"
echo "  goal.md: $GOALSPEC_ROOT/active/goal.md"
echo "next: fill in active/goal.md (intake agent), then 'goalspec review prompt intake'"
