#!/usr/bin/env bash
# Fills packaging/aur/PKGBUILD for a release tag: pkgver from the tag, and the
# sha256 of the Linux tarball read from the release's own SHA256SUMS — the
# authoritative list the release publishes — rather than recomputed from a fresh
# download. Same reasoning as the Homebrew updater: reading the published list
# pins exactly what the release shipped.
#
# Publishing to the AUR is a separate maintainer step (an AUR account and a
# registered SSH key): after this runs, on an Arch machine do
# `makepkg --printsrcinfo > .SRCINFO` and push to ssh://aur@aur.archlinux.org.
# See docs/BUILD.md, "AUR package".
#
# SHA256SUMS is consumed only after SHA256SUMS.minisig verifies against the
# repository's minisign.pub. Set SHA256SUMS_FILE (and, optionally,
# SHA256SUMS_SIGNATURE_FILE) to verify a local pair instead of fetching one.
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <tag> [pkgbuild-file]" >&2
  exit 1
fi

case "$TAG" in
  v*) VERSION="${TAG#v}" ;;
  *)  VERSION="$TAG"; TAG="v$TAG" ;;
esac

if [[ "$VERSION" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for the AUR package." >&2
  exit 0
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "AUR version must be a stable x.y.z release, got '$VERSION'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PKGBUILD="${2:-$REPO_ROOT/packaging/aur/PKGBUILD}"
if [ ! -f "$PKGBUILD" ]; then
  echo "PKGBUILD not found: $PKGBUILD" >&2
  exit 1
fi

RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/$TAG}"
ASSET="ocideck-linux-x64-$VERSION.tar.gz"

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
  echo "SHA256SUMS.minisig verification failed; refusing to update PKGBUILD." >&2
  exit 1
fi

# Match the tarball by its bare name, tolerating the leading "./" that
# `sha256sum ./*` writes into the list.
SHA="$(awk -v f="$ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print $1 }' "$SUMS")"
if ! printf '%s\n' "$SHA" | grep -Eq '^[0-9A-Fa-f]{64}$'; then
  echo "No unique, valid SHA-256 for $ASSET found in verified SHA256SUMS." >&2
  exit 1
fi
SHA="$(printf '%s' "$SHA" | tr '[:upper:]' '[:lower:]')"

sed -i.bak \
  -e "s|^pkgver=.*|pkgver=$VERSION|" \
  -e "s|^sha256sums=.*|sha256sums=('$SHA')|" \
  "$PKGBUILD"
rm -f "$PKGBUILD.bak"

echo "Updated $PKGBUILD to $VERSION (sha256 $SHA)."
echo "Next (maintainer, on Arch): makepkg --printsrcinfo > .SRCINFO, then push to the AUR."
