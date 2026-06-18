#!/usr/bin/env bash
# yq_cmd.sh — `goalspec yq` subcommand: manage the framework's yq dependency.
#
# Subcommands:
#   goalspec yq which       Print the yq binary the framework would use right
#                           now (system mikefarah v4, else vendored runtime/bin
#                           binary) and the detection details.
#   goalspec yq install     Download a mikefarah yq v4 binary matching this host
#                           into <project>/.goalspec/runtime/bin/ (SHA256
#                           verified). Use this when the host OS/arch was not
#                           pre-vendored or you gitignored the binaries.
#
# This script is reached via the dispatch *pre-init* case on purpose: `yq install`
# must be runnable when NO yq exists yet (the normal load.sh yq gate would
# otherwise exit 1 before the command runs).
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$SRC_ROOT/runtime/lib/yq.sh"
# common.sh gives us goalspec_find_root (does not need yq).
# shellcheck disable=SC1091
. "$SRC_ROOT/runtime/lib/common.sh"

GOALSPEC_YQ_VERSION="v4.52.5"
GOALSPEC_YQ_RELEASE_BASE="https://github.com/mikefarah/yq/releases/download/${GOALSPEC_YQ_VERSION}"

_yq_die() { echo "goalspec: error: $*" >&2; exit 1; }

# Resolve the project-local .goalspec root to install into (prefer $PWD's).
_yq_target_root() {
  local root=""
  if [ -d "$PWD/.goalspec" ] && [ -f "$PWD/.goalspec/runtime/lib/yq.sh" ]; then
    root="$PWD/.goalspec"
  else
    goalspec_find_root 2>/dev/null && root="$GOALSPEC_ROOT"
  fi
  [ -n "$root" ] || _yq_die "not inside a goalspec project (run from a project that has .goalspec/runtime/)"
  echo "$root"
}

_yq_usage() {
  cat <<EOF
usage: goalspec yq <which|install>

  which      Show the yq binary the framework resolves to for this host.
  install    Download a matching mikefarah yq ${GOALSPEC_YQ_VERSION} into
             <project>/.goalspec/runtime/bin/ (use when no compatible yq is
             installed and the host OS/arch was not pre-vendored).
EOF
}

cmd_which() {
  local os arch sys resolved
  os="$(_goalspec_yq_os)"
  arch="$(_goalspec_yq_arch)"
  if _goalspec_yq_system_v4; then
    sys="$(command -v yq) ($(command yq --version 2>/dev/null | tr -d '\n'))"
  else
    sys="(none / not mikefarah v4)"
  fi
  resolved="$(goalspec_yq_resolve "$(_yq_target_root 2>/dev/null || echo "$SRC_ROOT")")"
  cat <<EOF
host:              ${os}/${arch}
system yq:         ${sys}
vendored expected: $(_yq_target_root 2>/dev/null || echo "$SRC_ROOT")/runtime/bin/yq-${os}-${arch}$([ "$os" = windows ] && echo .exe)
resolved (used):   ${resolved:-<none — run 'goalspec yq install'>}
EOF
  [ -n "$resolved" ]
}

cmd_install() {
  local root os arch asset bin tmp expected_sha actual_sha
  root="$(_yq_target_root)"
  os="$(_goalspec_yq_os)"
  arch="$(_goalspec_yq_arch)"
  [ -n "$os" ] && [ -n "$arch" ] || _yq_die "cannot detect host OS/arch (uname -s/-m)"
  asset="yq_${os}_${arch}"
  bin="$root/runtime/bin/yq-${os}-${arch}"
  [ "$os" = "windows" ] && { asset="${asset}.exe"; bin="${bin}.exe"; }
  mkdir -p "$root/runtime/bin"

  echo "goalspec yq install: fetching mikefarah yq ${GOALSPEC_YQ_VERSION} for ${os}/${arch}"
  tmp="$(mktemp)"
  if ! curl -fsSL "${GOALSPEC_YQ_RELEASE_BASE}/${asset}" -o "$tmp"; then
    rm -f "$tmp"
    _yq_die "download failed for ${asset} (${GOALSPEC_YQ_RELEASE_BASE}/${asset}). This OS/arch may not have a prebuilt release."
  fi

  # Verify against the official multi-algorithm `checksums` file (one line per
  # asset, filename first, then many algorithm hashes). Extract every 64-hex
  # token on the asset's line and accept a match against any (sha256 / etc.).
  local sums
  sums="$(mktemp)"
  if curl -fsSL "${GOALSPEC_YQ_RELEASE_BASE}/checksums" -o "$sums" 2>/dev/null && [ -s "$sums" ]; then
    actual_sha="$(sha256sum "$tmp" | awk '{print $1}')"
    expected_tokens="$(awk -v a="$asset" '$1==a{$1=""; print}' "$sums" | grep -oE '[0-9a-f]{64}' | sort -u)"
    if [ -n "$expected_tokens" ]; then
      if printf '%s\n' "$expected_tokens" | grep -qxF "$actual_sha"; then
        echo "  sha256 verified: ${actual_sha}"
      else
        rm -f "$tmp" "$sums"
        _yq_die "sha256 mismatch for ${asset}: got ${actual_sha}"
      fi
    else
      echo "  warn: no checksum entry for ${asset}; skipping verification"
    fi
  else
    echo "  warn: could not fetch checksums file; skipping sha256 verification"
  fi
  rm -f "$sums"

  mv -f "$tmp" "$bin"
  [ "$os" != "windows" ] && chmod +x "$bin"
  # Activate it in this process too.
  goalspec_setup_yq "$root" >/dev/null || _yq_die "downloaded ${bin} but resolver failed to validate it"
  echo "  installed: ${bin}"
  echo "  version:   $(yq --version 2>/dev/null)"
  echo "goalspec yq install: done"
}

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  which)   cmd_which ;;
  install) cmd_install ;;
  ""|-h|--help|help) _yq_usage ;;
  *) _yq_usage; exit 2 ;;
esac
