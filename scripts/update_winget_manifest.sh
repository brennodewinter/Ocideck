#!/usr/bin/env bash
# Generates a WinGet Community Repository manifest from a published OciDeck
# release. The installer stays on the canonical LibreKAT forge; WinGet is only
# an extra, replaceable index pointing at those versioned bytes.
#
# The hash comes from the release's own SHA256SUMS, rather than from a fresh
# download, so the manifest describes exactly what the release says it shipped.
# Set SHA256SUMS_FILE to a local list for an offline run (and for tests).
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <tag> [output-root]" >&2
  exit 1
fi

TAG="$1"
case "$TAG" in
  v*) VERSION="${TAG#v}" ;;
  *)  VERSION="$TAG"; TAG="v$TAG" ;;
esac

if [[ "$VERSION" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for WinGet." >&2
  exit 0
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "WinGet version must be a stable x.y.z release, got '$VERSION'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$REPO_ROOT/packaging/winget"
OUTPUT_ROOT="${2:-$REPO_ROOT/dist/winget}"
OUTPUT_DIR="$OUTPUT_ROOT/manifests/l/LibreKAT/OciDeck/$VERSION"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/$TAG}"
ASSET="ocideck-windows-x64-setup-$VERSION.exe"
INSTALLER_URL="$RELEASE_BASE_URL/$ASSET"

TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$TMP_WORK"' EXIT

if [ -n "${SHA256SUMS_FILE:-}" ]; then
  SUMS="$SHA256SUMS_FILE"
else
  curl -fsSLo "$TMP_WORK/SHA256SUMS" "$RELEASE_BASE_URL/SHA256SUMS"
  SUMS="$TMP_WORK/SHA256SUMS"
fi

SHA="$(awk -v f="$ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print toupper($1) }' "$SUMS")"
if ! [[ "$SHA" =~ ^[0-9A-F]{64}$ ]]; then
  echo "No valid SHA-256 for $ASSET found in SHA256SUMS." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
for template in "$TEMPLATE_DIR"/*.yaml.tmpl; do
  name="$(basename "$template" .tmpl)"
  sed \
    -e "s|{{VERSION}}|$VERSION|g" \
    -e "s|{{TAG}}|$TAG|g" \
    -e "s|{{INSTALLER_URL}}|$INSTALLER_URL|g" \
    -e "s|{{INSTALLER_SHA256}}|$SHA|g" \
    "$template" > "$OUTPUT_DIR/$name"
done

echo "Wrote WinGet manifest for OciDeck $VERSION to $OUTPUT_DIR"
echo "Validate on Windows: winget validate --manifest \"$OUTPUT_DIR\""
