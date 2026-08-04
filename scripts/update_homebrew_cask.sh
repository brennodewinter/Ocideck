#!/usr/bin/env bash
# Fills homebrew/ocideck.rb.tmpl for a release tag and writes the cask.
#
# Homebrew Cask is macOS-only — there are no Linux casks — so this handles the
# macOS artifact only. A Linux install path lives on its own track (issue #1227).
#
# The SHA-256 is read from the release's own SHA256SUMS, the list the release
# publishes, rather than recomputed from a fresh download. Recomputing would pin
# whatever this run happened to fetch; reading the published list pins exactly
# what the release shipped. Set SHA256SUMS_FILE to read a local list instead of
# fetching one (used by the test).
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <tag> [output-file]" >&2
  exit 1
fi

TAG="$1"
OUTPUT_FILE="${2:-}"

case "$TAG" in
  v*) VERSION="${TAG#v}" ;;
  *)  VERSION="$TAG" ;;
esac

if [[ "$TAG" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for the Homebrew cask update." >&2
  exit 0
fi

RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/$TAG}"
MACOS_ASSET="ocideck-macos-$VERSION.zip"
MACOS_URL="$RELEASE_BASE_URL/$MACOS_ASSET"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if [ -n "${SHA256SUMS_FILE:-}" ]; then
  SUMS="$SHA256SUMS_FILE"
else
  curl -fsSLo "$TMPDIR/SHA256SUMS" "$RELEASE_BASE_URL/SHA256SUMS"
  SUMS="$TMPDIR/SHA256SUMS"
fi

# Match the asset by its bare name, tolerating the leading "./" that
# `sha256sum ./*` writes into the list.
MACOS_SHA="$(awk -v f="$MACOS_ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print $1 }' "$SUMS")"
if [ -z "$MACOS_SHA" ]; then
  echo "No SHA-256 for $MACOS_ASSET found in SHA256SUMS." >&2
  exit 1
fi

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
  -e "s|{{MACOS_SHA256}}|$MACOS_SHA|g" \
  "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Wrote $OUTPUT_FILE"
