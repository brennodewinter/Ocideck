# Packaging

Linux install formats for OciDeck — Phase 1 of the broad-distro route
([issue #1227](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/1227),
design in [`../docs/design/LINUX_PACKAGING.md`](../docs/design/LINUX_PACKAGING.md)).

Every format here wraps the **same** `flutter build linux` bundle the release
already ships as a tarball. None of them is a store, a gatekeeper or a sandbox:
the direct download from the forge stays canonical, and these are extra doors to
the same house. The confined formats (Flatpak, Snap) are a separate, later track
— they need the capability feature-flag first; see the design doc.

## What is here

| Path | What it is |
| --- | --- |
| `linux/com.dewinter.ocideck.desktop` | Desktop entry, shared by the .deb, .rpm and AppImage. Keyed on the application id `com.dewinter.ocideck` — the same id the GTK runner sets as its default icon name (`linux/runner/my_application.cc`). |
| `linux/AppRun` | AppImage entrypoint: execs `ocideck` from the AppDir root. |
| `aur/PKGBUILD` | AUR `ocideck-bin`: installs the release tarball on Arch/Manjaro. |

The icon is **not** stored here: the bundle already ships `data/icons/app_icon.png`
(512 px), and the packaging pulls it straight from the built bundle so there is
one source of truth.

## How the release builds them

The Linux release job (`.forgejo/workflows/release.yml`) runs, after
`make build-linux`:

```
make package-linux VERSION=<version>     # -> scripts/package_linux.sh
```

which produces, into `dist/`:

- `ocideck-linux-x86_64-<version>.AppImage` — one runnable file, most distros
- `ocideck-linux-amd64-<version>.deb` — Debian / Ubuntu / Mint
- `ocideck-linux-x86_64-<version>.rpm` — Fedora / openSUSE

Each needs its own tool: `dpkg-deb` (base system), `rpmbuild` (the `rpm`
package, installed by the job) and `appimagetool`. The `.rpm` deliberately lets
rpmbuild derive its `Requires` from the ELF's sonames, so it resolves on both
Fedora and openSUSE without hardcoded package names; the `.deb` lists
`libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, liblzma5`, with alternatives that
bridge Debian and Ubuntu 24.04's `t64` renames.

## The appimagetool pin

`appimagetool` is packaged by no distribution and ships only a rolling
`continuous` tag, so there is no version number to monitor. It is therefore
pinned **by sha256** in the release job (`APPIMAGETOOL_SHA256`): the hash is the
immutable identity of the exact bytes. If upstream rebuilds `continuous`, the
download stops matching and the job fails **loudly** rather than silently running
a different binary — the same "no silent drift" property `.github/pinned-ci-versions.json`
gives the version-pinned tools, reached a different way (which is why appimagetool
is not in that manifest: a content-hash pin cannot go stale by omission).

**To re-pin** (only when the build fails on a sha256 mismatch, or you deliberately
want a newer appimagetool): fetch the new digest and update `APPIMAGETOOL_SHA256`
in `.forgejo/workflows/release.yml`.

```bash
curl -fsSL https://api.github.com/repos/AppImage/appimagetool/releases/tags/continuous \
  | jq -r '.assets[] | select(.name=="appimagetool-x86_64.AppImage") | .digest'
```

## Publishing the AUR package

`aur/PKGBUILD` is ready but publishing is a maintainer step (it needs an AUR
account and a registered SSH key — the same kind of one-off credential setup as
the Homebrew tap). Per release:

```bash
scripts/update_aur_pkgbuild.sh v<version>     # fills pkgver + sha256 from SHA256SUMS
# then, on an Arch machine:
makepkg --printsrcinfo > .SRCINFO
git commit -am "ocideck-bin <version>" && git push aur master
```

## Note on `StartupWMClass`

The desktop entry sets `StartupWMClass=ocideck` (the binary name, the usual X11
WM_CLASS instance for a Flutter Linux app). On Wayland the compositor matches the
window's app-id (`com.dewinter.ocideck`) to the desktop-file basename instead, so
that path needs no hint. If a running window ever fails to group under its launcher
icon, check the real value with `xprop WM_CLASS` and adjust this one line.

## Testing

The packages themselves are only built on a Linux tag, so no `flutter test`
produces one. `test/linux_packaging_test.dart` pins the wiring offline — the job
calls the packager and uploads every artifact it makes, the script names those
exact artifacts and declares the right runtime libraries, appimagetool is
checksum-verified, and the metadata is well formed. Validate the actual packages
with a prerelease tag (`v<next>-rc1`, which builds and publishes as a prerelease
without touching the live web demo or the website) before the real release.
