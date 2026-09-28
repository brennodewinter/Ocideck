#!/usr/bin/env bash
# Fills homebrew/ocideck.rb.tmpl for a release tag and writes the cask.
#
# Homebrew Cask is macOS-only — there are no Linux casks — so this handles the
# macOS artifact only. A Linux install path lives on its own track (issue #1227).
#
# The SHA-256 is read from the release's own SHA256SUMS, the list the release
# publishes, rather than recomputed from a fresh download. Recomputing would pin
# whatever this run happened to fetch; reading the published list pins exactly
# what the release shipped. The list is trusted only after its detached
# SHA256SUMS.minisig verifies against the repository's minisign.pub. Set
# SHA256SUMS_FILE (and, optionally, SHA256SUMS_SIGNATURE_FILE) to verify a local
# pair instead of fetching the public pair.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <tag> [output-file]" >&2
  exit 1
fi

TAG="$1"
OUTPUT_FILE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

case "$TAG" in
  v*) VERSION="${TAG#v}" ;;
  *)  VERSION="$TAG"; TAG="v$TAG" ;;
esac

if [[ "$VERSION" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for the Homebrew cask update." >&2
  exit 0
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Homebrew version must be a stable x.y.z release, got '$VERSION'." >&2
  exit 1
fi

RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/$TAG}"
MACOS_ASSET="ocideck-macos-$VERSION.zip"
MACOS_URL="$RELEASE_BASE_URL/$MACOS_ASSET"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if [ -n "${SHA256SUMS_FILE:-}" ]; then
  SOURCE_SUMS="$SHA256SUMS_FILE"
  SOURCE_SIGNATURE="${SHA256SUMS_SIGNATURE_FILE:-${SHA256SUMS_FILE}.minisig}"
  [ -f "$SOURCE_SUMS" ] || {
    echo "SHA256SUMS file not found: $SOURCE_SUMS" >&2
    exit 1
  }
  [ -f "$SOURCE_SIGNATURE" ] || {
    echo "SHA256SUMS signature not found: $SOURCE_SIGNATURE" >&2
    exit 1
  }
  cp "$SOURCE_SUMS" "$TMPDIR/SHA256SUMS"
  cp "$SOURCE_SIGNATURE" "$TMPDIR/SHA256SUMS.minisig"
else
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    -o "$TMPDIR/SHA256SUMS" "$RELEASE_BASE_URL/SHA256SUMS"
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    -o "$TMPDIR/SHA256SUMS.minisig" "$RELEASE_BASE_URL/SHA256SUMS.minisig"
fi
SUMS="$TMPDIR/SHA256SUMS"
SIGNATURE="$TMPDIR/SHA256SUMS.minisig"
PUBKEY="$REPO_ROOT/minisign.pub"

command -v minisign >/dev/null 2>&1 || {
  echo "minisign verifier not found" >&2
  exit 1
}
[ -f "$PUBKEY" ] || {
  echo "minisign public key not found: $PUBKEY" >&2
  exit 1
}
if ! minisign -Vm "$SUMS" -x "$SIGNATURE" -p "$PUBKEY" -q; then
  echo "SHA256SUMS.minisig verification failed; refusing to update the Homebrew cask." >&2
  exit 1
fi

# Match the asset by its bare name, tolerating the leading "./" that
# `sha256sum ./*` writes into the list.
MACOS_SHA="$(awk -v f="$MACOS_ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print $1 }' "$SUMS")"
if ! printf '%s\n' "$MACOS_SHA" | grep -Eq '^[0-9A-Fa-f]{64}$'; then
  echo "No unique, valid SHA-256 for $MACOS_ASSET found in verified SHA256SUMS." >&2
  exit 1
fi
MACOS_SHA="$(printf '%s' "$MACOS_SHA" | tr '[:upper:]' '[:lower:]')"

if [ -z "$OUTPUT_FILE" ]; then
  OUTPUT_FILE="$REPO_ROOT/homebrew/ocideck.rb"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
TEMPLATE_FILE="${TEMPLATE_FILE:-$REPO_ROOT/homebrew/ocideck.rb.tmpl}"

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
