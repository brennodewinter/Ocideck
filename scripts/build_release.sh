#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

require_cmd flutter
require_cmd dart
require_cmd make

section "OciDeck release build"
echo "Workspace: $ROOT_DIR"
echo "Flutter: $(flutter --version | sed -n '1p')"

section "Web"
echo "Building hardened web bundle and verifying CSP/CanvasKit hardening."
make check-web

section "macOS"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds the macOS app, so it must run on macOS." >&2
  exit 1
fi
echo "Building release .app."
make build-macos

section "Artifacts"
echo "Web deploy directory:"
echo "  $ROOT_DIR/build/web"
echo
echo "macOS release app directory:"
echo "  $ROOT_DIR/build/macos/Build/Products/Release"
echo
echo "Release build complete."
