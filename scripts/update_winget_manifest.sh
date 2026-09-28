#!/usr/bin/env bash
# Generates a WinGet Community Repository manifest from a published OciDeck
# release. The installer stays on the canonical LibreKAT forge; WinGet is only
# an extra, replaceable index pointing at those versioned bytes.
#
# The hash comes from the release's own SHA256SUMS, rather than from a fresh
# download, so the manifest describes exactly what the release says it shipped.
# The list is consumed only after SHA256SUMS.minisig verifies against the
# repository's minisign.pub. Set SHA256SUMS_FILE (and, optionally,
# SHA256SUMS_SIGNATURE_FILE) to verify a local pair for an offline run.
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
  cp "$SOURCE_SUMS" "$TMP_WORK/SHA256SUMS"
  cp "$SOURCE_SIGNATURE" "$TMP_WORK/SHA256SUMS.minisig"
else
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    -o "$TMP_WORK/SHA256SUMS" "$RELEASE_BASE_URL/SHA256SUMS"
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    -o "$TMP_WORK/SHA256SUMS.minisig" "$RELEASE_BASE_URL/SHA256SUMS.minisig"
fi
SUMS="$TMP_WORK/SHA256SUMS"
SIGNATURE="$TMP_WORK/SHA256SUMS.minisig"
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
  echo "SHA256SUMS.minisig verification failed; refusing to write a WinGet manifest." >&2
  exit 1
fi

SHA="$(awk -v f="$ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print toupper($1) }' "$SUMS")"
if ! [[ "$SHA" =~ ^[0-9A-F]{64}$ ]]; then
  echo "No unique, valid SHA-256 for $ASSET found in verified SHA256SUMS." >&2
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
