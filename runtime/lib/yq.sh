#!/usr/bin/env bash
# yq.sh — portable mikefarah-yq resolver.
#
# Why this exists: the framework has ~294 `yq ...` call sites (mikefarah v4
# dialect: `yq e`, `-i`, `-o=json`, `load()`, `del()`, array `select()`, ...).
# Target environments may not have `yq` installed, so this module makes the
# framework self-contained:
#
#   1. If the system has a compatible mikefarah yq v4 -> use it (fast path).
#   2. Otherwise use a vendored static binary from <root>/runtime/bin/
#      matching the host OS/arch (incl. Windows under Git Bash/MSYS).
#   3. If neither exists -> fail with a clear, actionable error.
#
# It is INTENTIONALLY dependency-free (no goalspec_die / common.sh symbols) so
# that early-running scripts like init.sh / install_ai.sh can source it before
# any other lib. goalspec_setup_yq defines a `yq()` shell FUNCTION that every
# bare `yq` call in the process resolves to — zero edits at call sites.
#
# Recursion safety: detection uses `command yq` (bypasses any function), and
# the override calls either `command yq` or an absolute vendored path — never a
# bare `yq`.

# Canonical OS string from `uname -s`.
# MINGW*/MSYS*/CYGWIN* (Git Bash / MSYS2 / Cygwin on Windows) -> "windows".
_goalspec_yq_os() {
  local s
  s="$(uname -s 2>/dev/null)" || s=""
  case "$s" in
    Linux)                             echo linux ;;
    Darwin)                            echo darwin ;;
    MINGW*|MSYS*|CYGWIN*|mingw*|msys*) echo windows ;;
    FreeBSD)                           echo freebsd ;;
    OpenBSD)                           echo openbsd ;;
    NetBSD)                            echo netbsd ;;
    *)                                 echo "$s" ;;
  esac
}

# Canonical arch string from `uname -m`.
_goalspec_yq_arch() {
  local m
  m="$(uname -m 2>/dev/null)" || m=""
  case "$m" in
    x86_64|amd64)        echo amd64 ;;
    aarch64|arm64|armv8l) echo arm64 ;;
    i386|i486|i586|i686) echo 386 ;;
    armv7l|armv6l)       echo arm ;;
    *)                   echo "$m" ;;
  esac
}

# Return 0 if a compatible mikefarah yq v4 is reachable on PATH.
# Uses `command yq` to bypass any previously-defined `yq()` function.
_goalspec_yq_system_v4() {
  command -v yq >/dev/null 2>&1 || return 1
  # mikefarah yq prints "... version v4.x.x"; kislyuk yq (jq wrapper) and
  # mikefarah v3 are NOT compatible with this framework's expressions.
  command yq --version 2>/dev/null | grep -qi 'version v4' || return 1
  # Final sanity probe: an eval expression must actually work.
  command yq e '1' >/dev/null 2>&1 || return 1
  return 0
}

# Resolve the absolute path/command to use for yq against <root> (default
# $GOALSPEC_ROOT). Prints either "yq" (use system) or an absolute vendored
# binary path. Prints nothing and returns 1 if nothing usable is available.
goalspec_yq_resolve() {
  local root="${1:-${GOALSPEC_ROOT:-}}"
  # Fast path: compatible system yq.
  if _goalspec_yq_system_v4; then
    echo yq
    return 0
  fi
  [ -n "$root" ] || return 1
  local os arch bin
  os="$(_goalspec_yq_os)"
  arch="$(_goalspec_yq_arch)"
  [ -n "$os" ] && [ -n "$arch" ] || return 1
  bin="$root/runtime/bin/yq-${os}-${arch}"
  [ "$os" = "windows" ] && bin="${bin}.exe"
  if [ -f "$bin" ]; then
    echo "$bin"
    return 0
  fi
  return 1
}

# Define the `yq()` function override for this process. Optional arg: framework
# root (defaults to $GOALSPEC_ROOT). Should be called once after the root is
# known (load.sh end, or top of init.sh / install_ai.sh via $SRC_ROOT).
goalspec_setup_yq() {
  local root="${1:-${GOALSPEC_ROOT:-}}"
  local resolved
  resolved="$(goalspec_yq_resolve "$root")"
  if [ -z "$resolved" ]; then
    local os arch
    os="$(_goalspec_yq_os)"
    arch="$(_goalspec_yq_arch)"
    cat >&2 <<EOF
goalspec: error: no usable yq found.
  goalspec needs mikefarah yq v4 (Linux/macOS/Windows, x86_64/arm64).
  Detected host: ${os}/${arch}
  - Install yq: https://github.com/mikefarah/yq#install
  - Or run: goalspec yq install   (downloads a matching binary into runtime/bin/)
  - Note: the kislyuk/jq-based 'yq' is NOT compatible.
EOF
    return 1
  fi
  if [ "$resolved" = "yq" ]; then
    # System mikefarah v4. `command yq` avoids recursing into this function.
    yq() { command yq "$@"; }
  else
    _GS_YQ_BIN="$resolved"
    [ -x "$resolved" ] || chmod +x "$resolved" 2>/dev/null || true
    yq() { "$_GS_YQ_BIN" "$@"; }
  fi
  export _GS_YQ_BIN
}
