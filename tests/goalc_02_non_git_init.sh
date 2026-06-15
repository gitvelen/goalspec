#!/usr/bin/env bash
# GOALC #2: `goalspec init` outside a git repo must fail with a clear message.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO="$TESTS_TMP_ROOT/non-git-$$"
/bin/rm -rf "$REPO"; mkdir -p "$REPO"; cd "$REPO"
# explicitly NOT a git repo.
if bash "$FRAMEWORK/goalspec" init >/dev/null 2>&1; then
  bad "init succeeded in a non-git directory"
else
  ok "init refused in non-git directory"
fi

# error message should hint at git init.
err="$(bash "$FRAMEWORK/goalspec" init 2>&1 >/dev/null || true)"
echo "$err" | /bin/grep -qi 'git' || bad "error does not mention git"

[ "$TESTS_FAIL" -eq 0 ]
