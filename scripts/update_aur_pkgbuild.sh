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
# Set SHA256SUMS_FILE to read a local list instead of fetching one (the test does).
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <tag> [pkgbuild-file]" >&2
  exit 1
fi

case "$TAG" in
  v*) VERSION="${TAG#v}" ;;
  *)  VERSION="$TAG" ;;
esac

if [[ "$TAG" == *-* ]]; then
  echo "Skipping prerelease tag $TAG for the AUR package." >&2
  exit 0
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
  SUMS="$SHA256SUMS_FILE"
else
  curl -fsSLo "$TMPDIR/SHA256SUMS" "$RELEASE_BASE_URL/SHA256SUMS"
  SUMS="$TMPDIR/SHA256SUMS"
fi

# Match the tarball by its bare name, tolerating the leading "./" that
# `sha256sum ./*` writes into the list.
SHA="$(awk -v f="$ASSET" '{ n = $2; sub(/^\.\//, "", n); if (n == f) print $1 }' "$SUMS")"
if [ -z "$SHA" ]; then
  echo "No sha256 for $ASSET found in SHA256SUMS." >&2
  exit 1
fi

sed -i.bak \
  -e "s|^pkgver=.*|pkgver=$VERSION|" \
  -e "s|^sha256sums=.*|sha256sums=('$SHA')|" \
  "$PKGBUILD"
rm -f "$PKGBUILD.bak"

echo "Updated $PKGBUILD to $VERSION (sha256 $SHA)."
echo "Next (maintainer, on Arch): makepkg --printsrcinfo > .SRCINFO, then push to the AUR."
