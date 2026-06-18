#!/usr/bin/env bash
# load.sh — source all runtime libs into the current shell.
# Command scripts source this once at the top.

GOALSPEC_LIB_DIR="${GOALSPEC_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Resolve framework root from script path that sourced this (caller is
# runtime/commands/<cmd>.sh; framework root is two levels up).
if [ -z "${GOALSPEC_ROOT:-}" ]; then
  GOALSPEC_ROOT="$(cd "$GOALSPEC_LIB_DIR/../.." && pwd)"
  PROJECT_ROOT="$(dirname "$GOALSPEC_ROOT")"
  export GOALSPEC_ROOT PROJECT_ROOT
fi

# yq resolver must load FIRST so its `yq()` override is in place before any
# lib that might invoke yq at source time (and so all bare `yq` call sites in
# the command body resolve to a system-or-vendored mikefarah v4 binary).
# shellcheck disable=SC1091
. "$GOALSPEC_LIB_DIR/yq.sh"
# shellcheck disable=SC1091
for lib in common hash state stale schema git scope intake validate; do
  . "$GOALSPEC_LIB_DIR/${lib}.sh"
done

# Now that GOALSPEC_ROOT is known, install the yq() override for this process.
goalspec_setup_yq "$GOALSPEC_ROOT" || exit 1
