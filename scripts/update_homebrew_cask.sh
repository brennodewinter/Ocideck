#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <tag> [output-file]" >&2
  exit 1
fi

TAG="$1"
OUTPUT_FILE="${2:-}"

if [[ "$TAG" == v* ]]; then
  VERSION="${TAG#v}"
else
  VERSION="$TAG"
fi

if [[ "$TAG" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for the Homebrew cask update." >&2
  exit 0
fi

RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/$TAG}"
MACOS_URL="${RELEASE_BASE_URL}/ocideck-macos-$VERSION.zip"
LINUX_URL="${RELEASE_BASE_URL}/ocideck-linux-x64-$VERSION.tar.gz"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSLo "$TMPDIR/macos.zip" "$MACOS_URL"
curl -fsSLo "$TMPDIR/linux.tar.gz" "$LINUX_URL"

compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

MACOS_SHA="$(compute_sha256 "$TMPDIR/macos.zip")"
LINUX_SHA="$(compute_sha256 "$TMPDIR/linux.tar.gz")"

if [ -z "$OUTPUT_FILE" ]; then
  OUTPUT_FILE="$PWD/homebrew/ocideck.rb"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
TEMPLATE_FILE="${TEMPLATE_FILE:-$PWD/homebrew/ocideck.rb.tmpl}"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Template file not found: $TEMPLATE_FILE" >&2
  exit 1
fi

sed \
  -e "s|{{VERSION}}|$VERSION|g" \
  -e "s|{{TAG}}|$TAG|g" \
  -e "s|{{MACOS_URL}}|$MACOS_URL|g" \
  -e "s|{{LINUX_URL}}|$LINUX_URL|g" \
  -e "s|{{MACOS_SHA256}}|$MACOS_SHA|g" \
  -e "s|{{LINUX_SHA256}}|$LINUX_SHA|g" \
  "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Wrote $OUTPUT_FILE"
