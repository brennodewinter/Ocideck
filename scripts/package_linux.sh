#!/usr/bin/env bash
# Packages the built Linux bundle into portable, self-hostable formats.
#
# Alongside the raw tarball the release already ships, produce
#
#   * an AppImage — one runnable file, the Linux counterpart of "the zip you open"
#   * a .deb      — Debian / Ubuntu / Mint, the largest desktop-Linux group
#   * an .rpm     — Fedora / openSUSE, essentially free next to the .deb
#   * a Flatpak   — direct download with explicit sandbox permissions
#
# Each wraps the same bundle the forge release publishes, so direct download
# stays canonical. Flatpak needs the GNOME 50 runtime; Snap is a later track.
#
# Run this after `make build-linux`. The requested files land in $OUT.
#
#   scripts/package_linux.sh 0.3.2                 # all four formats into dist/
#   FORMATS="deb" scripts/package_linux.sh 0.3.2   # just the .deb (local checks)
#   OUT=. scripts/package_linux.sh v0.3.2          # leading v is stripped
#
# Each format needs its own tool on the machine: `dpkg-deb` for the .deb,
# `rpmbuild` for the .rpm, `flatpak` for Flatpak and `appimagetool` for AppImage. appimagetool is
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
FORMATS="${FORMATS:-appimage deb rpm flatpak}"

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
  #
  # libayatana-appindicator3-1 joined the list with the nativeapi migration
  # (#1741): cnativeapi links it on Linux for the tray. It is a system library,
  # so the Flutter bundle does not carry it — without this line the package
  # installs and then fails to start on a machine that lacks it.
  cat > "$root/DEBIAN/control" <<EOF
Package: ocideck
Version: $VERSION
Architecture: amd64
Maintainer: $MAINTAINER
Installed-Size: $size_kb
Depends: libgtk-3-0t64 | libgtk-3-0, libsecret-1-0 | libsecret-1-0t64, liblzma5, libayatana-appindicator3-1, libgles2, libegl1, libpulse0
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
Requires:       libGLESv2.so.2()(64bit)
Requires:       libEGL.so.1()(64bit)

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
  # appimagetool shells out to `file` to detect the payload architecture and
  # bails with "file command is missing but required" if it is absent. It is not
  # in a minimal ubuntu image, so check for it here with a clear message rather
  # than letting appimagetool fail cryptically deep in the run (broke v0.3.3).
  require file "AppImage (appimagetool invokes it)"
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

# --- Flatpak ------------------------------------------------------------------

build_flatpak() {
  require flatpak "Flatpak bundle"
  require git "Flatpak native Git support"
  require dpkg-query "Flatpak component inventory"
  require python3 "Flatpak component inventory"
  local root="$TMPROOT/flatpak" repo="$TMPROOT/flatpak-repo"
  local out="$OUT/ocideck-linux-x86_64-$VERSION.flatpak"
  local notices="$root/files/share/doc/ocideck-flatpak"
  local packages=(git libayatana-appindicator3-1 libayatana-indicator3-7 \
    libayatana-ido3-0.4-0 libdbusmenu-glib4 libdbusmenu-gtk3-4 \
    libcurl3t64-gnutls librtmp1 libssh-4 libldap2 libsasl2-2)
  local -a source_paths
  mapfile -d '' -t source_paths < <(find "$(command -v git)" "$(git --exec-path)" \
    /usr/share/git-core/templates \( -type f -o -type l \) -print0)
  install -d "$root/files/lib/ocideck" "$root/files/bin"
  cp -a "$BUNDLE_DIR/." "$root/files/lib/ocideck/"
  install -m0755 "$(command -v git)" "$root/files/bin/git"
  install -d "$root/files/libexec/git-core" "$root/files/share/git-core"
  cp -a "$(git --exec-path)/." "$root/files/libexec/git-core/"
  cp -a /usr/share/git-core/templates "$root/files/share/git-core/"
  # GNOME's runtime provides GTK and libsecret, but not Ayatana or Git's curl variant.
  local soname library
  for soname in libayatana-appindicator3.so.1 libayatana-indicator3.so.7 \
      libayatana-ido3-0.4.so.0 libdbusmenu-glib.so.4 libdbusmenu-gtk3.so.4 \
      libcurl-gnutls.so.4 librtmp.so.1 libssh.so.4 libldap.so.2 liblber.so.2 \
      libsasl2.so.2; do
    library="$(ldconfig -p | awk -v name="$soname" '$1 == name { print $NF; exit }')"
    if [ -z "$library" ]; then
      echo "Required Flatpak library '$soname' not found." >&2
      exit 1
    fi
    install -m0644 "$library" "$root/files/lib/ocideck/lib/$soname"
    source_paths+=("$(readlink -f "$library")")
  done
  local -A known_packages=()
  local package source_file owner_line owner
  for package in "${packages[@]}"; do known_packages["$package"]=1; done
  for source_file in "${source_paths[@]}"; do
    owner_line="$(dpkg-query -S -- "$source_file")" || {
      echo "Flatpak source file has no package owner: $source_file" >&2
      exit 1
    }
    owner="${owner_line%%: *}"
    if [[ "$owner_line" == *$'\n'* || -z "${known_packages[${owner%%:*}]+x}" ]]; then
      echo "Flatpak source file is outside the inventoried packages: $source_file ($owner)" >&2
      exit 1
    fi
  done
  install -d "$notices/licenses"
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' \
    "${packages[@]}" > "$notices/PACKAGES.tsv"
  for package in "${packages[@]}"; do
    install -m0644 "/usr/share/doc/$package/copyright" \
      "$notices/licenses/$package.copyright"
  done
  (cd "$root/files" && find bin/git libexec/git-core share/git-core/templates \
    lib/ocideck/lib/libayatana*.so* lib/ocideck/lib/libdbusmenu*.so* \
    lib/ocideck/lib/libcurl-gnutls.so* lib/ocideck/lib/librtmp.so* \
    lib/ocideck/lib/libssh.so* lib/ocideck/lib/libldap.so* \
    lib/ocideck/lib/liblber.so* lib/ocideck/lib/libsasl2.so* \
    \( -type f -o -type l \) -print0 | sort -z | xargs -0 sha256sum) \
    > "$notices/FILES.sha256"
  python3 "$SCRIPT_DIR/flatpak_components.py" \
    "$notices/PACKAGES.tsv" "$notices/FILES.sha256" "$VERSION" \
    "$notices/components.cdx.json"
  cat > "$root/files/bin/ocideck" <<'WRAP'
#!/bin/sh
export GIT_EXEC_PATH=/app/libexec/git-core
export GIT_TEMPLATE_DIR=/app/share/git-core/templates
export LD_LIBRARY_PATH=/app/lib/ocideck/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /app/lib/ocideck/ocideck "$@"
WRAP
  chmod 0755 "$root/files/bin/ocideck"
  install -Dm0644 "$DESKTOP" "$root/files/share/applications/$APP_ID.desktop"
  install -Dm0644 "$ICON_SRC" \
    "$root/files/share/icons/hicolor/512x512/apps/$APP_ID.png"
  install -d "$root/var"
  cat > "$root/metadata" <<EOF
[Application]
name=$APP_ID
runtime=org.gnome.Platform/x86_64/50
sdk=org.gnome.Sdk/x86_64/50
command=ocideck
EOF
  # This wraps the already-built Flutter bundle; no Flatpak SDK build is needed.
  # build-finish's icon validator starts bubblewrap, which nested CI containers
  # cannot use; the same checked files are exported directly instead.
  flatpak build-finish --no-exports "$root" \
    --share=ipc --share=network --socket=x11 --socket=wayland \
    --socket=pulseaudio --device=dri --filesystem=home \
    --talk-name=org.freedesktop.secrets >/dev/null
  install -Dm0644 "$DESKTOP" "$root/export/share/applications/$APP_ID.desktop"
  install -Dm0644 "$ICON_SRC" \
    "$root/export/share/icons/hicolor/512x512/apps/$APP_ID.png"
  # Only the icon validator runs without bubblewrap; the shipped app retains
  # the permissions above. Forgejo's Docker runner cannot nest namespaces.
  flatpak build-export --disable-sandbox "$repo" "$root" stable >/dev/null
  flatpak build-bundle "$repo" "$out" "$APP_ID" stable >/dev/null
  cp "$notices/components.cdx.json" "$out.cdx.json"
  echo "  + $(basename "$out")"
}

# --- Drive --------------------------------------------------------------------

echo "== OciDeck package: Linux ($FORMATS) $VERSION -> $OUT =="
for fmt in $FORMATS; do
  case "$fmt" in
    appimage) build_appimage ;;
    deb)      build_deb ;;
    rpm)      build_rpm ;;
    flatpak)  build_flatpak ;;
    *) echo "Unknown format '$fmt' (want: appimage deb rpm flatpak)." >&2; exit 1 ;;
  esac
done
echo "== done =="
