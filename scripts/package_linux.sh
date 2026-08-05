#!/usr/bin/env bash
# Packages the built Linux bundle into portable, self-hostable formats.
#
# Phase 1 of the Linux install route (issue #1227, docs/design/LINUX_PACKAGING.md):
# alongside the raw tarball the release already ships, produce
#
#   * an AppImage — one runnable file, the Linux counterpart of "the zip you open"
#   * a .deb      — Debian / Ubuntu / Mint, the largest desktop-Linux group
#   * an .rpm     — Fedora / openSUSE, essentially free next to the .deb
#
# None of these is a gatekeeper or a sandbox: each just wraps the same bundle the
# forge release publishes, so the direct download stays canonical. The confined
# formats (Flatpak / Snap) are a separate, later track — they need the capability
# feature-flag first (see the design doc).
#
# Run this after `make build-linux`. The requested files land in $OUT.
#
#   scripts/package_linux.sh 0.3.2                 # all three formats into dist/
#   FORMATS="deb" scripts/package_linux.sh 0.3.2   # just the .deb (local checks)
#   OUT=. scripts/package_linux.sh v0.3.2          # leading v is stripped
#
# Each format needs its own tool on the machine: `dpkg-deb` for the .deb,
# `rpmbuild` for the .rpm, and `appimagetool` for the AppImage. appimagetool is
# not packaged by any distro, so it is fetched and sha256-verified (set
# APPIMAGETOOL_URL + APPIMAGETOOL_SHA256, as the release workflow does) unless
# one is already on PATH or named by $APPIMAGETOOL. A missing tool is a hard
# error, not a silent skip — a release must not quietly ship fewer formats than
# it promises.
set -euo pipefail

# --- Where things are ---------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VERSION="${1:-${VERSION:-}}"
VERSION="${VERSION#v}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>   (or set VERSION=...)" >&2
  exit 1
fi

BUNDLE_DIR="${BUNDLE_DIR:-$REPO_ROOT/build/linux/x64/release/bundle}"
OUT="${OUT:-$REPO_ROOT/dist}"
FORMATS="${FORMATS:-appimage deb rpm}"

if [ ! -x "$BUNDLE_DIR/ocideck" ]; then
  echo "No Linux bundle at $BUNDLE_DIR — run 'make build-linux' first." >&2
  exit 1
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# --- Shared package metadata --------------------------------------------------

APP_ID="com.dewinter.ocideck"          # the GTK application id baked into the runner
DESKTOP="$REPO_ROOT/packaging/linux/$APP_ID.desktop"
ICON_SRC="$BUNDLE_DIR/data/icons/app_icon.png"   # 512px, shipped inside the bundle
MAINTAINER="Stichting LibreKAT <security@librekat.nl>"
HOMEPAGE="https://pawprint.vigilis.online/LibreKAT/Ocideck"
SUMMARY="Presentation tool where the content, not the canvas, is the document"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "Required tool '$1' not found — needed to build the $2." >&2
  echo "Install it, or narrow FORMATS to skip that format." >&2
  exit 1
}

# Lay the install tree the .deb and .rpm share: the bundle under
# /usr/lib/ocideck, a tiny /usr/bin/ocideck wrapper onto it, and the desktop
# entry plus themed icon so the app shows up in menus.
stage_fhs() {
  local root="$1"
  install -d "$root/usr/lib/ocideck"
  cp -a "$BUNDLE_DIR/." "$root/usr/lib/ocideck/"

  install -d "$root/usr/bin"
  cat > "$root/usr/bin/ocideck" <<'WRAP'
#!/bin/sh
exec /usr/lib/ocideck/ocideck "$@"
WRAP
  chmod 0755 "$root/usr/bin/ocideck"

  install -Dm0644 "$DESKTOP" "$root/usr/share/applications/$APP_ID.desktop"
  install -Dm0644 "$ICON_SRC" \
    "$root/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
}

# --- .deb ---------------------------------------------------------------------

build_deb() {
  require dpkg-deb ".deb package"
  local root="$TMPROOT/deb"
  stage_fhs "$root"

  install -d "$root/DEBIAN"
  local size_kb
  size_kb="$(du -sk "$root/usr" | cut -f1)"
  # Alternatives on the GTK/secret names bridge Debian and Ubuntu 24.04+, which
  # renamed several libs for the 64-bit time_t transition (libgtk-3-0t64). apt
  # picks the first line that exists on the running distro.
  cat > "$root/DEBIAN/control" <<EOF
Package: ocideck
Version: $VERSION
Architecture: amd64
Maintainer: $MAINTAINER
Installed-Size: $size_kb
Depends: libgtk-3-0t64 | libgtk-3-0, libsecret-1-0 | libsecret-1-0t64, liblzma5
Section: office
Priority: optional
Homepage: $HOMEPAGE
Description: $SUMMARY
 OciDeck edits Marp Markdown decks: plain text you can read, diff and keep.
 The content is the document; the app renders it to slides, PDF and HTML,
 fully offline. This package wraps the same bundle the OciDeck release ships.
EOF

  local out="$OUT/ocideck-linux-amd64-$VERSION.deb"
  # --root-owner-group writes root:root without needing fakeroot.
  dpkg-deb --root-owner-group --build "$root" "$out" >/dev/null
  echo "  + $(basename "$out")"
}

# --- .rpm ---------------------------------------------------------------------

build_rpm() {
  require rpmbuild ".rpm package"
  local root="$TMPROOT/rpm-stage"
  stage_fhs "$root"

  # rpm forbids '-' in a Version; an rc tag (0.3.2-rc1) becomes 0.3.2~rc1, which
  # also sorts before the final release, exactly as a pre-release should.
  local rpmver="${VERSION//-/\~}"
  local top="$TMPROOT/rpmbuild"
  install -d "$top/SPECS" "$top/BUILD" "$top/RPMS"

  cat > "$top/SPECS/ocideck.spec" <<EOF
Name:           ocideck
Version:        $rpmver
Release:        1
Summary:        $SUMMARY
License:        EUPL-1.2
URL:            $HOMEPAGE
BuildArch:      x86_64

# The payload is a prebuilt Flutter bundle — no sources, no compilation. Skip the
# debuginfo split (nothing to attach) and the strip/brp post-install scripts that
# would rewrite the shipped .so files. rpmbuild still scans the ELF and bundled
# libraries and emits soname Requires (libgtk-3.so.0, libsecret-1.so.0,
# liblzma.so.5, ...) that Fedora and openSUSE both provide — distro-agnostic,
# unlike hardcoded package names. The bundled libraries become Provides in the
# same package, so their Requires resolve internally.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
OciDeck edits Marp Markdown decks: plain text you can read, diff and keep.
The content is the document; the app renders it to slides, PDF and HTML,
fully offline. This package wraps the same bundle the OciDeck release ships.

%install
mkdir -p %{buildroot}
cp -a %{stagedir}/. %{buildroot}/

%files
%{_prefix}/lib/ocideck
%{_bindir}/ocideck
%{_datadir}/applications/$APP_ID.desktop
%{_datadir}/icons/hicolor/512x512/apps/$APP_ID.png
EOF

  # QA_RPATHS masks the $ORIGIN/lib rpath check (bit 0) and the standard-dirs
  # check (bit 4); the bundle deliberately links against its own lib/ dir.
  QA_RPATHS=0x0003 rpmbuild \
    --define "_topdir $top" \
    --define "stagedir $root" \
    -bb "$top/SPECS/ocideck.spec" >/dev/null

  local built="$top/RPMS/x86_64/ocideck-$rpmver-1.x86_64.rpm"
  local out="$OUT/ocideck-linux-x86_64-$VERSION.rpm"
  cp "$built" "$out"
  echo "  + $(basename "$out")"
}

# --- AppImage -----------------------------------------------------------------

resolve_appimagetool() {
  if [ -n "${APPIMAGETOOL:-}" ]; then return 0; fi
  if command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL="$(command -v appimagetool)"
    return 0
  fi
  if [ -n "${APPIMAGETOOL_URL:-}" ] && [ -n "${APPIMAGETOOL_SHA256:-}" ]; then
    local dst="$TMPROOT/appimagetool"
    echo "  fetching appimagetool (sha256-pinned)"
    curl -fsSLo "$dst" "$APPIMAGETOOL_URL"
    echo "$APPIMAGETOOL_SHA256  $dst" | sha256sum -c - >/dev/null
    chmod +x "$dst"
    APPIMAGETOOL="$dst"
    return 0
  fi
  echo "appimagetool not found. Put it on PATH, set APPIMAGETOOL=/path/to/it," >&2
  echo "or set APPIMAGETOOL_URL + APPIMAGETOOL_SHA256 to fetch it verified." >&2
  exit 1
}

build_appimage() {
  require curl "AppImage (to fetch appimagetool)"
  resolve_appimagetool

  local appdir="$TMPROOT/AppDir"
  install -d "$appdir"
  cp -a "$BUNDLE_DIR/." "$appdir/"                       # ocideck, lib/, data/

  install -m0755 "$REPO_ROOT/packaging/linux/AppRun" "$appdir/AppRun"
  # appimagetool wants the .desktop and its Icon= file at the AppDir root.
  install -m0644 "$DESKTOP" "$appdir/$APP_ID.desktop"
  install -m0644 "$ICON_SRC" "$appdir/$APP_ID.png"
  # And the same under usr/share so an installed AppImage integrates into menus.
  install -Dm0644 "$DESKTOP" "$appdir/usr/share/applications/$APP_ID.desktop"
  install -Dm0644 "$ICON_SRC" \
    "$appdir/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

  local out="$OUT/ocideck-linux-x86_64-$VERSION.AppImage"
  # APPIMAGE_EXTRACT_AND_RUN lets appimagetool (itself an AppImage) run without
  # FUSE, which a container does not have.
  ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$appdir" "$out" >/dev/null
  echo "  + $(basename "$out")"
}

# --- Drive --------------------------------------------------------------------

echo "== OciDeck package: Linux ($FORMATS) $VERSION -> $OUT =="
for fmt in $FORMATS; do
  case "$fmt" in
    appimage) build_appimage ;;
    deb)      build_deb ;;
    rpm)      build_rpm ;;
    *) echo "Unknown format '$fmt' (want: appimage deb rpm)." >&2; exit 1 ;;
  esac
done
echo "== done =="
