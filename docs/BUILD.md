# OciDeck — Build & Release

> **Status:** procedure, current — and the authority on the toolchain pin · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

How to build OciDeck from source and produce distributable apps.

## Prerequisites

> **This section is the authority on toolchain versions.** `CONTRIBUTING.md`,
> [`CONTRIBUTING_GUIDELINES.md`](CONTRIBUTING_GUIDELINES.md) and
> [`DEVELOPMENT_SETUP_GUIDE.md`](DEVELOPMENT_SETUP_GUIDE.md) point here rather
> than repeating a number; when one of them disagrees with this section, this
> section wins, and when this section disagrees with `.tool-versions`, that file
> wins. *(Noted 2026-07-22: those documents had drifted into two different
> answers — "3.44+ / 3.12+" in one place and "3.44.6 / 3.12.2" in two others —
> without either saying which one mattered and why.)*

- **Flutter 3.47.1** (stable) — the exact version CI pins (see `.tool-versions`
  and both `.github/workflows/*.yml`). Only Flutter is pinned; the Dart SDK comes
  bundled with it, and `pubspec.yaml` merely constrains it (`sdk: ^3.12.0`).
  Building tolerates
  3.44+, but **`make format-check` is version-sensitive**: a different
  `dart format` reflows whitespace and fails the gate. Use the Flutter-bundled
  `dart` (not a separately installed standalone Dart, which can drift) so
  `make format-check` stays reproducible across machines. Check with
  `flutter --version`.

  In short: *build* with 3.44 or newer if you must, but *pass the gate* with
  3.47.1. The two are different requirements and only the second is enforced.
- A desktop toolchain for your target:
  - **macOS**: Xcode + CocoaPods.
  - **Windows**: Visual Studio with the "Desktop development with C++" workload.
  - **Linux**: see Flutter's Linux desktop prerequisites (GTK, clang, ninja, etc.).
- Enable the desktop target once if needed, e.g. `flutter config --enable-macos-desktop`.

## Get dependencies

```sh
make setup        # flutter pub get
```

OciDeck uses two **vendored plugin forks** under `third_party/`, wired through
`pubspec.yaml` (a path dependency for `desktop_multi_window`) and
`dependency_overrides` (`screen_retriever_macos`, and a pin of
`video_player_avfoundation`). `flutter pub get` resolves these automatically — no
extra steps. See [`ARCHITECTURE.md`](ARCHITECTURE.md#vendored-forks).

## Run

```sh
flutter run -d macos     # or -d windows / -d linux / -d chrome
```

## Web

OciDeck also builds for the browser. Use the hardened target:

```sh
make build-web        # flutter build web --release --no-web-resources-cdn --csp
```

Note this target has prerequisites: it first runs `deps-verify-offline` (bundled-JS
integrity against the manifest) and `sbom-verify` (SBOM drift), either of which can
fail the build *before* Flutter is invoked. Afterwards it runs
`tool/pack_web_release.dart` (see [What travels with the bundle](#what-travels-with-the-bundle))
and normalises file permissions.

The two flags make the bundle **self-contained and CSP-safe**:

- `--no-web-resources-cdn` self-hosts CanvasKit instead of fetching it from the
  gstatic CDN, so the running app pulls **zero third-party origins**.
- `--csp` emits a loader with no `eval()`/inline scripts, so it runs under the
  strict Content-Security-Policy declared in `web/index.html` (`script-src 'self'
  'wasm-unsafe-eval'`, no `unsafe-inline`/`unsafe-eval`).

The UI font (Roboto) is bundled too, so the engine never reaches out to
`fonts.gstatic.com`. Remote deck media is blocked on web by that CSP by design;
to allow it, add `https:` to `img-src`/`media-src` in `web/index.html`.

Serve `build/web/` from any static host. The web build supports editing, preview,
HTML export, and presenting in a single window. Dual-screen presenter mode and
direct filesystem project folders are desktop-only; use **Open** / **Save** via
the browser file picker on web.

**Loading splash.** The CanvasKit build takes roughly ten seconds before it
paints anything; without something on screen in the meantime, that reads as a
plain white page — "it's broken", not "please wait" (#589). `web/index.html`
ships a static `#splash` layer under the app surface (`z-index: -1`) that
Flutter's own painting covers once it starts, so nothing needs to remove it. It
carries no `<script>` — the CSP's `script-src` has no `'unsafe-inline'`, so an
inline script would silently fail to run. `test/web_index_splash_test.dart` guards
both the layer's presence and its script-free body without needing a full web
build.

### What travels with the bundle

A bundle you hand to someone else is not just the app. `make build-web` finishes
by running `tool/pack_web_release.dart`, which puts four things in `build/web/`:

| Artefact | Why it must travel |
| --- | --- |
| `LICENSE.md` | Without its licence terms the bundle is not redistributable. This is the condition under which the dependencies themselves travel, not a courtesy. |
| `SOURCE.md` | `main.dart.js` is compiled; this says where the source is. EUPL-1.2 article 5 asks for the source or an indication of it when the Work is distributed **or communicated**, and article 1 counts hosting as communicating. Without it the licence grants a right to study and adapt that the recipient cannot exercise. |
| `THIRD_PARTY_NOTICES.md` | The attribution those dependencies require. See [LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md). |
| `sbom/` (CycloneDX, SPDX, Markdown) | The CRA inventory belongs to the exact build you hand out, not to the repository it came from. Served under `/sbom/`. See [SBOM.md](SBOM.md). |

It also **removes** `.last_build_id`, which Flutter leaves behind. That file is
an md5 over, among other things, the absolute path of the output directory on
the machine that built it, so two people building identical source get different
values. Sealed into `SHA256SUMS` it would guarantee that anyone who builds their
own copy can never reproduce a published digest — for a reason that has nothing
to do with the code.

The step ends by writing `SHA256SUMS` over the finished bundle, so it must stay
the last thing that touches file contents. It prints the sha256 of `SHA256SUMS`
itself — put that one value in the release announcement.

### Verifying a bundle you downloaded

`SHA256SUMS` is in the ordinary `sha256sum` format, so no OciDeck-specific tool
is needed:

```sh
cd ocideck-web && shasum -a 256 -c SHA256SUMS    # macOS/BSD
cd ocideck-web && sha256sum -c SHA256SUMS        # GNU coreutils
```

Every line must say `OK`. A `FAILED` line names the file that differs; a
`No such file` line names one that is missing.

That catches files that changed or went missing, but not a file that was
*added* — `SHA256SUMS` says nothing about a path it never mentions. Comparing
the path column against what is actually on disk closes that, again with
ordinary tools:

```sh
diff <(cut -c 67- SHA256SUMS | sort) \
     <(find . -type f | sed 's|^\./||' | grep -v '^SHA256SUMS$' | sort)
```

From a checkout, with the bundle in `build/web`, one command does both that and
the presence of the licence, source indication and SBOM:

```sh
dart run tool/pack_web_release.dart --check
```

**What this proves, and what it does not.** It lets you check that your copy is
complete and undamaged. On its own the list proves nothing — it only says
something once you set it against a value from another channel. It is **not a
signature**: whoever can replace the bundle can replace `SHA256SUMS` with it.

So compare the sha256 of `SHA256SUMS` itself against the value published in the
release announcement — one 64-character value, read over a channel other than
the one you downloaded from:

```sh
shasum -a 256 SHA256SUMS
```

That catches a damaged download, a modified mirror, and a third party rehosting
a changed bundle. It does **not** catch a compromise of our own publishing
chain: whoever can change both the download and the announcement changes both,
and you would see them agree. Only a signature or a reproducible build helps
there, and OciDeck now has both: every release manifest carries a minisign
signature (`SHA256SUMS.minisig`, #1014 — see [Signing the release
manifest](#signing-the-release-manifest-minisign)), and the web bundle is
content-reproducible within a fixed build environment (next section).

### Reproducible builds (web)

A signature says *who* stands behind the bytes. A reproducible build says
something stronger: rebuild from the same source and you get the same bytes, so
you need not trust our build machine at all. Building from source is already the
route KNOWN_LIMITATIONS points to; this makes it *verifiably identical*.

The hardened web bundle is content-reproducible **within a fixed build
environment**: two clean builds of the same source produce byte-identical files —
`main.dart.js`, CanvasKit, the service worker, the tree-shaken fonts and every
asset. One value used to differ every build: `serviceWorkerVersion` in
`flutter_bootstrap.js`, a random cache-buster for Flutter's (deprecated) service
worker. `tool/pack_web_release.dart` now normalises it to a value derived from
the service worker's own content — deterministic, and still a correct cache-buster
(it changes exactly when the service worker changes). This sits beside the
existing `.last_build_id` removal, which strips another build-machine-specific
value for the same reason.

**Verify it yourself.** Rebuild with the pinned toolchain and compare the
bundle-internal `SHA256SUMS` (which hashes each file's content) against the one in
the release you downloaded:

```sh
make build-web
shasum -a 256 build/web/SHA256SUMS      # compare this against the downloaded bundle's
```

If they match, the published bundle's contents came from this source, without
trusting our build machine. Verify the release-level `SHA256SUMS.minisig` on top
(above) to confirm the archive you downloaded is the one we published.

Set your expectations honestly: this is conclusive when you build with the pinned
toolchain from the same source. `main.dart.js` is deterministic — clean rebuilds
produce the same bytes, and the host OpenCV native-assets build does not enter the
web output (see *Scope, honestly* below). What this project has **not**
cross-checked is a build in a *different environment* — chiefly a different OS,
but also any machine not yet compared (the largest machine-specific input, the
absolute build path, was empirically found not to leak into the output, #1027;
dart2js is expected to be platform-independent, but that has been measured on one
machine only). So treat a **match** as the strong signal, and a **mismatch** as
"confirm you matched the build environment — toolchain, OS, and try another clean
checkout — then compare again", not as immediate proof of tampering.

**Scope, honestly.** Reproducibility is always relative to a build environment,
never "any machine, any tools". The Flutter toolchain is pinned
(`make check-toolchain`), dependencies are locked
(`flutter pub get --enforce-lockfile` on the release lane), and the source is
committed — so a same-machine rebuild from the same source is byte-identical
(verified). The native-assets layer (the `dartcv4` OpenCV build via CMake) builds
a *host* FFI library; web has no `dart:ffi`, so it is **not** part of the web
output and does not affect web reproducibility. (An earlier suspicion that it did
was traced to a contaminated experiment — a concurrent edit to a `lib/` source
file between builds — not the native-assets layer; #1033.) The edge that remains
is a build in a *different environment* (a different OS, or a machine not yet
cross-checked), so a mismatch in the recipe above points first at a
build-environment difference, not tampering. The reproducibility that *is* achieved
covers the bundle
**contents**, not the `.tar.gz` wrapper the release workflow adds (its mtimes and
gzip header are not normalised — and need not be, since verification compares
extracted contents). The full investigation and the per-platform weighing (why
macOS and Windows are deliberately out of scope) live in the repository at
`assurance/reproduceerbare-builds.md`.

### Response headers the host must add

The CSP in `web/index.html` is delivered via a `<meta>` tag, which covers most
directives — but browsers **ignore `frame-ancestors` (and `sandbox`/`report-*`)
when they arrive via `<meta>`**. To actually prevent clickjacking, the static
host must send these as HTTP **response headers** for the app's HTML:

```
Content-Security-Policy: frame-ancestors 'none'
X-Frame-Options: DENY
Strict-Transport-Security: max-age=63072000; includeSubDomains
```

`Strict-Transport-Security` has no `<meta>` equivalent at all — a browser only
honours it as a response header — so without the host sending it, the first
plaintext request stays available to whoever is on the path. `Referrer-Policy`
is the exception in this list: the bundle already ships it as a meta tag.

(When embedding the bundle inside Nextcloud, replace `'none'` with the host
origin instead of dropping the header.) Ideally serve the **entire** CSP as a
response header rather than relying on the meta tag. Example snippets:

- **nginx**: `add_header Content-Security-Policy "frame-ancestors 'none'" always; add_header X-Frame-Options "DENY" always; add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;`
- **Caddy**: `header Content-Security-Policy "frame-ancestors 'none'"`, `header X-Frame-Options "DENY"` and `header Strict-Transport-Security "max-age=63072000; includeSubDomains"`
- **Apache**: the bundle already **ships these** — see below.

**Apache: shipped in the bundle.** `web/.htaccess` carries the full set (the
entire CSP as a header, `X-Frame-Options: DENY`, `X-Content-Type-Options:
nosniff`, `Referrer-Policy: no-referrer`, a `Permissions-Policy`, and HSTS).
`flutter build web` copies it to `build/web/.htaccess`, so on an Apache host it
takes effect with no extra step — **provided** `mod_headers` is enabled and
`AllowOverride` for the web root permits `FileInfo` (or `All`). Where
`AllowOverride` is `Off` (the hardened default), `.htaccess` is ignored; copy the
same directives into the vhost/server config. `check_web_hardening.dart` fails
the build if the shipped `.htaccess` loses a header or its CSP drifts from the
`<meta>` one.

See [`HOSTING.md`](HOSTING.md) §3 for what `preload` would additionally commit
you to, and why it is not the default recommendation. Cross-Origin-Embedder-Policy
(`require-corp`) is deliberately **not** shipped — it can break cross-origin
resources and needs testing first.

> A plain `flutter build web` still works, but it falls back to the gstatic CDN
> and an `unsafe-*` loader — use `make build-web` so the hardening stays pinned.

### Deep link: app plus presentation in one URL

`https://<host>/?deck=<url>` opens OciDeck *and* fetches the presentation at the
address you pass (URL-encode it). The same import gate applies as for *Import
from URL*: the safety scan, the Marp check, and the CORS rules below. Example:

```
https://ocideck.librekat.nl/?deck=https%3A%2F%2Fexample.org%2Fdeck.ocideck
```

### Fetch-proxy for URL import (optional, recommended)

In the browser, *Import from URL* works directly only for sources that allow
CORS. To be able to open a deck from **any** URL, deploy the SSRF-guarded
fetch-proxy alongside the static bundle — see
[`server/fetch-proxy/README.md`](../server/fetch-proxy/README.md). The web app
falls back automatically to the same-origin path `/fetch-proxy?url=…`. Without
the proxy everything still works, and the error message explains the CORS
restriction.

*(Translated 2026-07-22: these two sections were the only Dutch inside an
otherwise English document.)*

## Quality gate

```sh
make check        # format-check + analyze + conventions + method-length + dead-code + coverage
```

## Building release apps

Each platform has a `make` target (each only builds on its own OS — Flutter
cannot cross-compile a desktop bundle):

```sh
make build-release  # verified web bundle + macOS .app
make build-macos     # flutter build macos --release    → build/macos/Build/Products/Release/*.app
make build-windows   # flutter build windows --release  → build/windows/x64/runner/Release
make build-linux     # flutter build linux --release    → build/linux/x64/release/bundle
make package-linux VERSION=<v>   # AppImage + .deb + .rpm from that bundle → dist/
make build-web       # hardened web bundle              → build/web
make build-all       # web + this machine's native desktop target
```

`make package-linux` needs a bundle from `make build-linux` first (it is not a
prerequisite, so the release job does not build twice) and the packaging tools
on the machine — see [Linux packaging](#linux-packaging).

Use `make build-release` for the normal manual release path on macOS. It runs
`make check-web` first, so the browser bundle is built with
`--no-web-resources-cdn --csp` and then verified for the strict CSP,
self-hosted CanvasKit, and bundled UI font before the macOS app is built.

`make build-all` builds the web bundle plus whichever desktop target matches the
host OS (web + macOS on a Mac, web + Linux on Linux). A desktop bundle cannot be
cross-compiled, so a bundle for another OS must be built on that OS — which is
what the release workflow does across runners (see [Cutting a
release](#cutting-a-release)). Artifacts land under `build/<platform>/`.

### macOS notes

- **Swift Package Manager is enabled** for this project (since #1733); it is
  Flutter's default and `pubspec.yaml` no longer turns it off. Most plugins are
  resolved through SPM, and CocoaPods only handles the ones that have not
  adopted it — today just `desktop_multi_window`, which is why the build prints
  "The following plugins do not support Swift Package Manager for macos". That
  message is expected and harmless. The `Podfile` still matters for those
  leftovers.
- **`video_player_avfoundation` is pinned** (see `dependency_overrides`) because a
  newer release ships a Swift module whose private Objective-C dependency isn't
  packaged correctly by CocoaPods on recent Xcode.
- **The `DartCvMacOS` link is silenced on purpose.** That pod (pulled in by
  `opencv_core`) vendors OpenCV as a quarter-gigabyte prebuilt universal
  `libopencv.a`. Most of its x86_64 half is Intel IPP object code assembled
  without a platform load command, and the pod adds a second `-lc++` on top of
  the one the toolchain already links, so linking that single target used to
  emit over ten thousand lines of `ld: warning: no platform load command found
  in '…libopencv.a[x86_64][…]', assuming: macOS` plus `ld: warning: ignoring
  duplicate libraries: '-lc++'`. None of it is our code and none of it is
  fixable from here, so the `post_install` hook in `macos/Podfile` gives *only*
  the `DartCvMacOS` target `OTHER_LDFLAGS = -Wl,-w` (silences that target's
  linker) plus `GCC_WARN_INHIBIT_ALL_WARNINGS`, which also drops the
  `-Wshorten-64-to-32` warnings from the pod's own `dartcv/core/mat.cpp` — the
  same treatment `video_player_avfoundation` already gets. Every other target,
  `Runner` first among them, still reports its warnings in full. If you ever need
  to inspect that pod's own build, drop the settings temporarily rather than
  widening them to the project.
- **CocoaPods + Ruby locale**: on some setups `pod install` (run by
  `flutter build macos`) fails with `Encoding::CompatibilityError` /
  "Unicode Normalization not appropriate for ASCII-8BIT". This is a Ruby/CocoaPods
  locale issue, not a project problem. Fix it by forcing a UTF-8 locale:

  ```sh
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  flutter build macos --release
  ```

- **Distribution**: a `.app` that opens on *other* Macs without a Gatekeeper
  warning must be Developer-ID-signed and notarised. That whole chain is
  automated — run `make notarize-macos`. See [Signing and notarising the macOS
  app](#signing-and-notarising-the-macos-app) below for the one-time setup.

### Signing and notarising the macOS app

`make build-macos` signs the app **ad-hoc** (`CODE_SIGN_IDENTITY = "-"`), which
runs only on the machine that built it. To hand the app to anyone else it must be
signed with a **Developer ID Application** certificate, built with the **hardened
runtime**, and **notarised** by Apple with the ticket stapled into the bundle —
otherwise Gatekeeper reports it as "damaged". `make notarize-macos` does the whole
chain (`scripts/notarize_macos.sh`): clean build → inside-out sign of every
embedded framework and then the bundle → local signature check → notarise →
staple → verify the way Gatekeeper does.

**One-time setup.**

1. **Certificate.** In Xcode → *Settings → Accounts*, add the Apple ID of the
   Developer Program membership, then *Manage Certificates… → + → Developer ID
   Application*. Confirm it landed:

   ```sh
   security find-identity -v -p codesigning
   # → Developer ID Application: <name> (<TEAMID>)
   ```

2. **Notary credentials.** `notarytool` must authenticate to Apple. The simplest
   is an app-specific password (create one at <https://account.apple.com> →
   *Sign-In and Security → App-Specific Passwords*), stored once in the
   **file-based login keychain** under a profile name:

   ```sh
   xcrun notarytool store-credentials \
     --keychain "$HOME/Library/Keychains/login.keychain-db" ocideck-notary \
     --apple-id "<apple-id-email>" --team-id <TEAMID>
   # paste the app-specific password when prompted
   ```

   The `--keychain` flag is not optional: without it `notarytool` saves into the
   session-bound data-protection ("Local Items") keychain, which disappears
   after a session or runner restart. The script reads the profile back from the
   default file keychain.

**Then, per release:**

```sh
make notarize-macos            # clean build + sign + notarise + staple + verify
# → build/macos/Build/Products/Release/OciDeck.app   (stapled, distributable)
# → build/macos/dist/OciDeck.zip                      (zipped for hand-off)
```

A successful run ends with `source=Notarized Developer ID`. The script defaults
to the identity `Developer ID Application: Brenno de Winter (AMT83P4B3L)` and the
profile `ocideck-notary`; override with `OCIDECK_SIGN_IDENTITY` /
`OCIDECK_NOTARY_PROFILE` for another signer or CI.
`scripts/notarize_macos.sh --skip-build` signs and notarises whatever is already
in `build/` without rebuilding.

### Windows / Linux notes

- Windows: distribute the contents of `build/windows/x64/runner/Release/`, or
  wrap that same bundle in the installer — see [Building the Windows
  installer](#building-the-windows-installer) below.
- **Windows-bestandsassociaties**: importeer
  [`windows/file-associations.reg`](../windows/file-associations.reg) (paden
  aanpassen) of neem de sleutels op in de installer. `.ocideck` opent dan
  direct met OciDeck; `.md` krijgt OciDeck als "Openen met…"-optie zonder de
  standaard over te nemen. De app opent het meegegeven pad bij het starten.
  macOS regelt hetzelfde via `CFBundleDocumentTypes` in `Info.plist`
  (`.ocideck` = Owner, `.md` = Alternate) — dat zit al in de app-bundel.
- Linux: distribute `build/linux/x64/release/bundle/` (shipped as a tarball), or
  build an AppImage, a `.deb` and an `.rpm` from it with `make package-linux` —
  see [Linux packaging](#linux-packaging). Flatpak/Snap are a separate, later
  track (#1227).

### Building the Windows installer

Unpacking a folder and making your own shortcut is a poor way to install
anything, so the Windows bundle can be wrapped in an ordinary installer (#1208):
Start menu shortcut, the file associations, and a clean uninstall through
*Programs and Features*. Needs [Inno Setup 6.3 or
newer](https://jrsoftware.org/isdl.php) on the machine — the release job pins
7.1.0, and the packager finds either major under either Program Files root — and
runs **on Windows only**, in the same bash `make build-windows` runs in (Git Bash
or MSYS2).

```sh
make build-windows            # -> build/windows/x64/runner/Release/
make build-windows-installer  # -> dist/ocideck-windows-x64-setup-<version>.exe
```

The second target deliberately does **not** depend on the first, for the same
reason `package-linux` does not depend on `build-linux`: it should package
exactly the bundle you just built and looked at, never quietly make a new one.
The version comes from `pubspec.yaml`, so the installer is not a second place to
bump a version number.

The script is `scripts/build_windows_installer.sh`; the installer itself is
declared in [`packaging/windows/ocideck.iss`](../packaging/windows/ocideck.iss).
It installs machine-wide by default (Program Files, associations for every user)
and offers a per-user install to anyone without admin rights — the registry keys
use Inno's `HKA` root, so one key list serves both. Those keys are the same set as
[`windows/file-associations.reg`](../windows/file-associations.reg), which stays
the hand-import route for people running the raw bundle.

**It is a dumb, offline installer, and that is a boundary rather than a gap.** No
auto-update, no version check, no release feed, no network access at all — see
[SECURITY.md](../SECURITY.md#how-a-fix-reaches-you).
`test/windows_packaging_test.dart` holds every property in this section: the two
association routes agreeing, the installer sourcing the build output whole rather
than a hand-picked file list, and the absence of any downloader or `[Code]`
section. Whether the installer *actually installs* is still a manual check on a
Windows machine — nothing verifies that automatically.

**The release builds it too** (#1583). The forge has no Windows machine, but the
mirror does: `.github/workflows/release.yml` on github.com builds the Windows
artifacts on every `v*` tag and publishes them as release assets, and the forge's
`windows-ophalen` job pulls both back with `curl` before anything is hashed. So a
tag now produces the installer alongside the zip, without a hand step. Locally the
two commands above remain the way to build and inspect one.

That lane runs `bash scripts/build_windows_installer.sh` directly rather than the
`make` target, because `make` is not reliably present on that runner — which is
why the packager is a script and the `make` target only wraps it. Inno Setup is
not preinstalled on `windows-latest` either (Server 2022 shipped it, Server 2025
does not), so the job downloads it from the publisher's own GitHub release,
pinned twice: by version (`INNOSETUP_VERSION`, mirrored in
`.github/pinned-ci-versions.json` so `make check-pins` notices it ageing) and by
sha256, so replaced bytes fail loudly instead of building quietly.

**Why the installer is built before the zip.** The packager signs `ocideck.exe`
and the DLLs *in place* when a certificate is configured. Zip first and you ship a
zip of unsigned binaries next to a signed installer — two downloads that are not
the same build. `test/windows_packaging_test.dart` pins that order.

**Provenance, with no certificate.** An installer asks for elevation, and an
unsigned one that asks for elevation teaches a worse habit than an unsigned app
you unzip yourself — people are trained to click through installer prompts. The
answer is not to withhold the installer but to anchor it: it lands in `dist/`
before the `Checksums` step, so it is listed in `SHA256SUMS` and therefore covered
by the minisign signature over that manifest, and the release notes carry the same
"verify your download" instruction the zip has. That signature is what stands in
for the Authenticode certificate this project has weighed and declined. A
published installer that was neither signed nor in the manifest would have no
provenance at all — a step backwards from the zip rather than a convenience, which
is why the fetch job refuses to finish unless *both* Windows files are there.

#### Signing it (optional)

Signing is off by default and the script says so loudly when it produced an
unsigned installer, so nobody ships one believing otherwise. Windows signing
remains the weighed decision recorded under [Signing status of the published
artifacts](#signing-status-of-the-published-artifacts) — the hook exists so that
a certificate is the only thing still missing, not a rewrite.

With a certificate present, set its thumbprint from the Windows certificate store
and the script signs `ocideck.exe`, the DLLs beside it, and the finished
installer, in that order:

```sh
OCIDECK_WIN_SIGN_SHA1=<certificate-thumbprint> make build-windows-installer
```

| Variable | Meaning |
| --- | --- |
| `OCIDECK_WIN_SIGN_SHA1` | Certificate thumbprint in the Windows certificate store. Unset = unsigned build with a warning. |
| `OCIDECK_WIN_SIGN_TIMESTAMP_URL` | RFC 3161 timestamp server. Defaults to DigiCert's. |
| `OCIDECK_SIGNTOOL` / `OCIDECK_ISCC` | Paths to `signtool.exe` / `ISCC.exe`, if they are not found automatically. |

There is deliberately **no** way to hand the script a `.pfx` and a password.
Since June 2023 every publicly trusted code-signing key must live on a hardware
token or an HSM, which prompts for its own PIN, so the signing material never
becomes an environment variable, a file in the tree, or a runner secret — the
same line `scripts/notarize_macos.sh` holds on macOS. Timestamping is not
optional either: without it a signature dies with the certificate, and since
March 2026 a code-signing certificate lasts at most 460 days.

Signing is all-or-nothing. Once a thumbprint is configured, a file that fails to
sign fails the build, because a half-signed installer looks trustworthy in
exactly the places people check.

### App icons

Six icon sets — macOS, Windows, Linux, web, iOS and Android — are cut from a
single master by one script. Run it after any change to the mark:

```bash
./scripts/regenerate_icons.sh
```

Then commit whatever it changed. It needs ImageMagick (`brew install
imagemagick`) and nothing else, and it is safe to run at any time: re-running it
without changing the master reproduces the committed macOS set byte for byte.

**The master is `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png`**,
not `assets/images/ocideck-logo.png`. The latter is the logo shown *inside* the
app: 512 px, with a wider margin. The master is 1024 px and carries roughly three
times the edge detail, so every app-icon size is a reduction and never an
enlargement — which is what keeps the 1024 icon Apple shows in the App Store
sharp. If you replace the master, keep its framing: the drawing trimmed, scaled
to **87.7%** of the canvas height, centred on opaque white. Opaque, not
transparent: the mark is dark ink and vanishes on a dark taskbar without the
white plate under it, and iOS rejects an icon with an alpha channel outright.

The web icons are the one deliberate exception — they come from
`assets/images/ocideck-logo.png` at its own wider margin, because a favicon sits
in a tab strip rather than a dock. That is measured, not assumed; the script says
so at the point where it does it.

`test/platform_icon_branding_test.dart` holds every target against the mark
afterwards. It compares the drawing itself — trimmed, flattened to a greyscale
fingerprint — so a target left behind at the next rebrand fails instead of
shipping, which is exactly what happened to Linux and Windows in June: the
rebrand regenerated only macOS and web, and those two carried the previous logo
for a month with nothing turning red.

`ios/` and `android/` are not supported build targets — the Makefile has no
target for them and the README does not list them. Their icon sets are kept in
step anyway: a set nobody watches is how this went wrong the first time.

## CI

> **Since 2026-07-23 the forge has an Actions runner.** The quality gate runs
> **on a `v*` tag** (`.forgejo/workflows/ci.yml`, #751/#790) — not per pull
> request. A gate run cost 22 minutes on the server's runner against 2.5 minutes
> locally, and that wait per PR did not earn its keep next to a `make check`
> every committer already runs before pushing. The honest consequence: CI is no
> longer a merge gate but a **release** gate. If it fails on a tag, the problem
> is already on `main`, and the assurance before `main` is — with one deliberate
> exception — entirely the committer's local run. That exception is
> `.forgejo/workflows/scans.yml` (#778): the secret and SAST scans do run on
> every pull request, because they cost seconds rather than minutes and
> because a credential found after the merge is in the history for good.
>
> Two later changes shaped what that gate is. It runs `make check-no-coverage`
> rather than `make check` (#796): the whole suite, without the coverage
> instrumentation that cost ~39% CPU — so the coverage floors are enforced
> locally and nowhere else. And since #797 it runs on the registered **Mac**
> runner rather than in a container on the server, because the 46-vs-2.5-minute
> gap was measured to be the machine (four cores of a 2018 Xeon against an M5
> Max), not the steps. `check-toolchain` runs inside the gate either way and
> still demands channel `stable`, the official origin, and equality with the
> pin.
>
> What that costs: the suite no longer runs on Linux by default. The Linux gate
> moved to `.forgejo/workflows/linux-gate.yml`, on demand — press it before a
> release and when a change touches paths, subprocesses or `git` invocations.
> The pinned-toolchain and pub caches live there, where an install actually
> happens.
>
> `.forgejo/workflows/linux-build.yml` and `.forgejo/workflows/macos-build.yml`
> produce the Linux and macOS desktop bundles **on demand only**
> (`workflow_dispatch`, since #790). They used to run on every push to `main`,
> which cost 17.5 minutes of runner time per merge while `release.yml` on the
> GitHub mirror already builds all three platforms on every `v*` tag. Building
> the same thing twice buys no extra assurance: the gate is what stops a
> regression, packaging afterwards is not. The macOS job runs on a registered
> Mac runner (host mode — Apple licenses macOS for Apple hardware only, so that
> job cannot run on the Linux server; when the Mac is offline the run waits). `make check-full` and the Windows/web bundles remain
> local: run the first before dependency or web-facing changes, and build
> those bundles on their target OS. See
> [CHECKS.md](CHECKS.md#continuous-integration).

`.github/workflows/ci.yml` *declares* the quality gate on Ubuntu for every push
and pull request (plus `flutter test` on macOS and Windows). It does not build
native binaries; it validates formatting, static analysis, and the test suite
(which are platform-independent).

`.github/workflows/release.yml` is the one file on the mirror that really runs:
it builds the **Windows** artifact, which the forge has no machine for. Both
workflows pin **Flutter 3.47.1** (stable), and `make check-toolchain` fails if
either line drifts from `.tool-versions`.

For the full check reference, see [`CHECKS.md`](CHECKS.md).

## Cutting a release

### `make release TAG=vX.Y.Z` — the orchestrator (#1161)

`make release TAG=vX.Y.Z` (a thin wrapper over `scripts/release.sh`) runs the
front of this chain so it happens the same way every time:

1. **Tag-guard** — refuses anything that is not a clean, strictly-higher release
   tag, without changing a thing: the tag must be `vX.Y.Z` (no pre-release/build
   suffix), must equal `v` + the version in `pubspec.yaml`, must not already
   exist, and must be a legal one-axis bump from the last release — the last
   check delegated to `make check-version-bump` (`tool/check_version_bump.dart`),
   so the semver rules live in exactly one, tested, place.
2. **Phase 1 (local, non-destructive)** — `make catalogs-outdated` (advisory),
   `make check-release`, `make build-release`, `make notarize-macos`.

The **irreversible, outward** steps are printed as ordered next steps rather than
fired automatically — pushing the tag, replacing the app in `/Applications`, and
the public distribution below. This is the **guided** variant: it removes the
repeatable toil (guard + validate + build) and keeps the irreversible acts
deliberate. Run the numbered steps it prints, then the sections below.

### `scripts/release_auto.sh` — the unattended variant (#1161)

When you want the *whole* chain to run hands-off, `scripts/release_auto.sh` is
the automated counterpart. It fronts **all** the interaction — a menu picks the
next SemVer level (patch/minor/major; there is no fourth digit, the project
promises strict three-part SemVer) and one prompt takes the minisign key
password — and then runs everything without another question, through the public
tag push, the signing and the web deploy. The password is held only in memory
and fed to `minisign` on standard input; the macOS notarisation leans on this
Mac's keychain items and asks for nothing.

*Before* the password it refuses to start while another Flutter or Dart process is
working in this same worktree. Phase 1 builds clean, and a clean build begins with
`flutter clean`; a `flutter run` you left open keeps refilling `.dart_tool`, which
`flutter clean` reports but survives with exit 0, so the next `dart run` dies on a
half-deleted `hooks_runner` cache ten minutes later — as the v0.4.4 run did. Close
the other process and start again. `scripts/notarize_macos.sh` checks the same
invariant directly (is `.dart_tool` actually gone?) so it also holds when you run
that script by hand.

Right after the password, a **pre-flight** checks everything the later,
irreversible steps will need — the forge token, the `mirror` remote, the deploy
host over ssh, a throwaway `minisign` signature, and the macOS signing identity
plus notary profile — so a wrong password or an unreachable host fails in
seconds, before the long build and the tag, instead of after (which is exactly
how a real release once stranded at the very end).

`scripts/release_auto.sh --preflight` runs that rehearsal on its own: the
staleness gate, a clean and idle worktree, the token, the mirror, the deploy
host, the signing key and the notary profile — then stops without mutating
anything or writing a release log. Run it before you set an evening aside for a
release; the expensive failures in this chain have all been knowable up front.

The order is the three phases in one go: **Phase 1 (local)** an *outdatedness
gate* over the bundled reference data, which now splits by *what* moved. If
upstream moved but the generated catalogue comes out word-for-word identical, the
drift is bookkeeping — a snapshot date in a constant and a row in
`LICENSE_COMPLIANCE.md` — and Phase 1 refreshes it itself, as its own commit on
the release branch, exactly like the scanner pins. If the refresh touches a
*generated* part (`*_data.dart`, `*_android.dart`, `*_ios.dart`) the chain stops:
that changes what a report cites, can touch translated text, and pulls the pinned
counts out from under the catalogue tests. Sources without a generator (CWE,
MIAUW) stop it right away, with the route that belongs to that source rather than
a generic "run refresh-catalogs" that would do nothing there. Either way
`make refresh-catalogs` is the one command that fetches and records the new
version. Then it always runs `make bump-scanner-pins`
(idempotent) so the CI scanners (gitleaks/trufflehog/semgrep) ride to their latest
upstream automatically instead of blocking a release — a bump, if any, becomes its
own commit on the release branch; then the four-place version bump, `make sbom`,
`make check-release`, `make build-release`, `make notarize-macos`, seal
verification and the `/Applications` swap; **Phase 2** branch → *if the scanners
were bumped, publish a new scans image first* (dispatch `ci-image-scans` on the
branch and wait, so `scans.yml`'s new image tag exists before the PR scan runs) →
PR → wait for the gate (up to `OCIDECK_GATE_TIMEOUT_MIN`, default 75 min: `linux-gate`
runs the full suite per-PR on a capacity-1 serial runner and can queue, so the wait
prints progress rather than giving up at 30) → merge → tag → push to origin **and**
mirror → poll the release CI until every job is done; **Phase 3** `make deploy-web`
*first* — the web
demo depends only on the web bundle, so a signing or platform failure never leaves
it on the old version — then sign `SHA256SUMS`, attach `SHA256SUMS.minisig`
(waiting up to a few minutes for `publiceren` to attach it rather than dying on a
404), and watch the website-downloads job.

The standalone `make bump-scanner-pins` does the same edit outside a release
(manifest + every workflow's `*_VERSION` env + the pre-baked scans image tag, in
sync); `DRY_RUN=1` shows what it would change. It does **not** publish the image
or commit — dispatch `ci-image-scans` (or `make ci-image-scans-publish`) and open
a PR yourself, exactly as `release_auto.sh` does inside a release. A newer scanner
can surface new findings, so the scan gate may still turn red and need addressing.

Restartable: if the chain breaks — a gate time-out, a network blip, a failed
upstream CI job — rerun `scripts/release_auto.sh --resume vX.Y.Z` and it picks up
where it left off. It reads what already exists on the forge — tag pushed? the
release PR merged, open, or only a branch? — and does *only* what remains,
idempotently; the expensive Phase 1 (build/notarize) is never redone. So a pre-tag
stall (the usual case — the gate simply took longer than the wait) resumes at the
gate/merge; a post-tag stall (Phase 3 signing/deploy, or an upstream job) resumes
at Phase 3. The PR is found by title, so it is still located after the branch is
deleted on merge, and the tag is placed on the PR's exact merge commit.

Fail-safe: `set -Eeuo pipefail` plus an `ERR` trap name *which* step failed on
*which* line, and whether the tag was already pushed — before the push nothing
went out and the local release branch is cleaned up (rerun fresh, or `--resume`
if the PR was already open). That clean-up reports what it actually did: if the
working tree blocks the checkout back to the branch you started from, the release
branch — carrying the version bump — is still there, and the script says so and
hands you the two commands to remove it. It used to swallow both failures and
claim success, which is how a version bump once ended up inherited by an unrelated
branch. After the push the tag stays put: finish the **same**
tag with `--resume vX.Y.Z`; only when a released artifact is itself wrong do you
cut the next patch tag — never a re-tag (that degrades the mirror Windows release
to a draft and leaves `windows-ophalen` waiting forever). `--dry-run` shows the
plan and the outdatedness gate without mutating anything; `--print-version LEVEL`
prints just the computed tag (the hermetic guard-arithmetic that
`test/release_auto_version_test.dart` pins against the canonical rule). A fresh run
bases the next version on `origin/main`, so re-running from a leftover release
branch cannot miscompute the bump; `--preflight` rehearses every precondition.
This is the fully-unattended increment the
guided `make release` deliberately left to a proven follow-up.

### The tag-driven chain

One tag produces everything. `git push origin v0.1.0` starts
`.forgejo/workflows/release.yml`, and about half an hour later there is a
release at
<https://pawprint.vigilis.online/LibreKAT/Ocideck/releases> carrying the web
bundle, the macOS app, the Linux packages (tarball plus AppImage, `.deb` and
`.rpm`), the Windows app, both SBOM formats and a `SHA256SUMS` over all of them —
and <https://ocideck.librekat.nl/> is serving that same web bundle.

### What runs where, and why

| Artifact | Built on | Why there |
| --- | --- | --- |
| Web bundle | forge `docker` runner, prebaked `ocideck-ci` image | `make check-web`: hardened build **and** its verification |
| Linux x64 — tarball, AppImage, `.deb`, `.rpm` | forge `docker` runner, prebaked `ocideck-ci` image | native desktop build on the baked toolchain, then `make package-linux` |
| macOS | forge, `macos` runner | Apple licenses macOS for Apple hardware only |
| Windows x64 | GitHub mirror | no Windows machine on the forge |
| SBOM | forge, from the repo | committed and kept current by `make sbom-verify` |

The Windows artifact travels back as a **public GitHub release asset**, not as a
build artifact. A GitHub artifact needs a token even on a public repository and
expires after ninety days; a release asset is a plain public URL that keeps
working. So *collecting* it needs no credentials — the `windows-ophalen` job just
`curl`s the URL.

*Starting* the build, however, is no longer left to chance. It used to rely on the
tag push to the mirror triggering `.github/workflows/release.yml` there — but when
the tag already exists on the mirror (an earlier attempt, or Forgejo's own push
mirror) that push is a no-op and GitHub fires **no** `push` event, so the Windows
build never starts and `windows-ophalen` waited out its 45-minute timeout (this
stranded `v0.3.6`). The job now **actively dispatches** the mirror workflow via
`workflow_dispatch` using the `GH_DISPATCH_TOKEN` secret (a fine-grained GitHub PAT
with *Actions: read and write* + *Contents: read* on `brennodewinter/Ocideck`),
regardless of whether the push event fired. It is idempotent — if the asset or a
running build already exists it does not dispatch again — and it polls the run
status so a failed build stops the job promptly (with the run URL) instead of
after 45 empty minutes. Without the secret the job falls back to the old passive
wait, so the chain keeps working until the secret is set.

The **web and Linux jobs run on the prebaked `ocideck-ci:flutter-<pin>` image** —
the same image the gates use (see the `ci-image.yml` section of
[CHECKS.md](CHECKS.md)) — so the build-toolchain and the pinned, sha256-verified
Flutter are baked in rather than installed on every tag. The Linux job additionally `apt-get install`s
`liblzma-dev`, `libsecret-1-dev` and `libayatana-appindicator3-dev`, which only
the desktop build links (via `flutter_secure_storage`, lzma and — since the
nativeapi migration, #1741 — `cnativeapi`'s tray) and the test-oriented image
does not carry, plus `rpm` for the packaging step's `rpmbuild`. The appindicator
module is the one of `cnativeapi`'s four pkg-config requirements that
`libgtk-3-dev` does not pull in, which is why its absence only surfaced at
`v0.4.9` — as a CMake error before a single file was compiled.
Both jobs share the gates' `pub`/`dartcv` `actions/cache` keys: `linux-gate`
populates them on every push to `main` — a scope a tag build can read — so the
expensive dartcv OpenCV compile is restored *warm* at tag time instead of rebuilt
from scratch. A cache miss is fail-open (it just rebuilds, as before). Together
this cut the Linux build from about seventy minutes at `v0.2.0` to under twenty at
the `v0.2.1-rc1` rehearsal (#1170, #1172).

### Homebrew cask (macOS)

Each non-prerelease tag also updates a Homebrew **cask**, so macOS users can
`brew install --cask librekat/ocideck/ocideck` after tapping our forge. The cask
is only a pointer: it
carries the release's download URL and the SHA-256 read straight from the
published `SHA256SUMS`, so `brew` fetches our own artifact and verifies it. It is
**macOS-only** — Homebrew Cask has no Linux equivalent; a Linux install path is
tracked separately (#1227).

- **Where it runs: in the tap, not here.** The tap updates *itself*.
  `.forgejo/workflows/update-cask.yml` in `LibreKAT/homebrew-ocideck` runs every
  30 minutes (and on `workflow_dispatch`), reads the newest non-prerelease from
  this repo's public API, fetches `scripts/update_homebrew_cask.sh` and
  `homebrew/ocideck.rb.tmpl` **at that tag** over `raw/<path>?ref=<tag>`,
  regenerates `Casks/ocideck.rb` and pushes — with the per-run Actions token
  Forgejo mints for that repository. Nothing is committed when the cask is
  already current, so the half-hourly schedule does not produce noise.

  Neither `release.yml` writes the cask any more. Until v0.4.8 the forge chain
  pushed it across with a personal token in `HOMEBREW_TAP_TOKEN`; the forge
  refused that token after an upgrade (HTTP 401) and the tap sat three releases
  behind before anyone noticed. Turning it around removed the secret entirely.
  The cost is that the cask trails a release by up to 30 minutes instead of
  updating within the run — irrelevant for a tap, since `brew update` is on the
  user's own clock, and worth it to be rid of a credential that expires.
- **This repo only supplies the building blocks**, and that coupling is silent:
  the tap fetches those two paths **by name**, from another repository. Rename or
  move either and the tap quietly keeps serving the previous release. There is no
  gate here that can see it, so `test/homebrew_cask_verify_test.dart` pins both
  paths; if you move them, update the workflow in the tap in the same change.
- **Tap topology: the forge is the source, GitHub is the backup.** The tap lives
  on our own forge as the canonical repo, **mirrored to GitHub** (a Forgejo
  push-mirror on the tap repo). Homebrew's one-argument shorthand
  (`brew tap brennodewinter/ocideck`) resolves to `github.com/...` *by
  definition*, so that form always installs from the mirror. The two-argument
  form taps any git URL, and that is the documented route in the README and the
  FAQ:

  ```sh
  brew tap librekat/ocideck https://pawprint.vigilis.online/LibreKAT/homebrew-ocideck.git
  brew install --cask librekat/ocideck/ocideck
  ```

  The GitHub shorthand stays documented as the fallback for when the forge is
  unreachable — a backup, not the source. (Both routes download the *app* from
  the forge either way; what differs is where the cask recipe comes from.)
- **One-time setup.** Create the tap repo `homebrew-ocideck` on the forge with a
  top-level `Casks/` directory, enable Actions on it, add `update-cask.yml`, and
  add a GitHub push-mirror to `brennodewinter/homebrew-ocideck`. **No secrets** —
  not on the tap and not on this repo. The old `HOMEBREW_TAP_REPOSITORY` and
  `HOMEBREW_TAP_TOKEN` secrets are unused; delete them and revoke the token.
- **The tap is read back, not assumed.** A workflow that runs green still says
  nothing about what is actually in the tap, so `scripts/verify_homebrew_cask.sh`
  re-reads `Casks/ocideck.rb` over the same public URL Homebrew itself uses and
  compares its `version` to the release. That check is the daily one below; run it
  by hand at any time, and without a tag it checks the newest release:

  ```bash
  scripts/verify_homebrew_cask.sh          # or: scripts/verify_homebrew_cask.sh v<version>
  ```
- **The mirror is checked daily, not at release time.** A stalled push-mirror is
  the same failure class one hop down: the forge tap is current, but everyone on
  the GitHub shorthand gets a stale cask. Push-mirroring is asynchronous, so
  checking it during the release run would go red on lag that is perfectly
  normal. `.forgejo/workflows/tap-mirror-check.yml` therefore runs
  `scripts/verify_homebrew_cask.sh --mirror` on a daily cron (and on
  `workflow_dispatch`), which tolerates a lag of `MIRROR_GRACE_HOURS` (24) after
  the release before it turns red. It re-checks the forge tap too, so a tap that
  somehow went stale is caught the next day rather than at the next release.
- **Caveat.** The cask is only a *smooth* install once the macOS release is
  notarised. An unsigned release (see the signing section above) installs fine
  via `brew` but Gatekeeper still blocks it on first launch — the cask eases
  distribution, not signing.

### Linux packaging

Homebrew Cask is macOS-only, so Linux has its own route (#1227). Phase 1 hangs
three portable formats — AppImage, `.deb` and `.rpm` — off every release, next
to the tarball — all wrapping the
same bundle, none a store or a sandbox. The design and the later phases (own
apt/rpm repo; Flatpak/Snap behind the capability feature-flag) are in
[`design/LINUX_PACKAGING.md`](design/LINUX_PACKAGING.md); the layout is in
[`../packaging/README.md`](../packaging/README.md).

- **Where it runs.** The `linux` job in `.forgejo/workflows/release.yml`, after
  `make build-linux`, runs `make package-linux` (→ `scripts/package_linux.sh`)
  and uploads all four assets in one artifact. `publiceren` then folds them into
  `SHA256SUMS` like every other file.
- **What it produces**, into `dist/`:
  `ocideck-linux-x86_64-<v>.AppImage`, `ocideck-linux-amd64-<v>.deb`,
  `ocideck-linux-x86_64-<v>.rpm` (each format's own arch label).
- **Tools.** `dpkg-deb` (base system), `rpmbuild` (the `rpm` package, added by
  the job) and `appimagetool`. The `.rpm` lets rpmbuild derive soname `Requires`
  so it resolves on Fedora and openSUSE alike; the `.deb` declares
  `libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, liblzma5`.
- **appimagetool is sha256-pinned** (`APPIMAGETOOL_SHA256` in the job), because it
  only ships a rolling `continuous` tag — there is no version to monitor, so the
  hash is the pin. A drift fails the build loudly; to re-pin, fetch the new digest
  (see [`../packaging/README.md`](../packaging/README.md)) and update the job.
- **Not offline-testable.** The packages only build on a Linux tag;
  `test/linux_packaging_test.dart` pins the wiring, but validate the real packages
  with a `-rc1` tag (below) before a real release.

### AUR package

`packaging/aur/PKGBUILD` is `ocideck-bin`: it installs the release tarball on
Arch/Manjaro, verified against the published `SHA256SUMS`. Publishing is a
maintainer step — it needs an AUR account and a registered SSH key, like the
Homebrew tap, so it is **not** wired into the release chain. Per release:

```bash
scripts/update_aur_pkgbuild.sh v<version>   # fills pkgver + sha256 from SHA256SUMS
# then on an Arch machine:
makepkg --printsrcinfo > .SRCINFO
git commit -am "ocideck-bin <version>" && git push aur master
```

### Before you tag

1. `make check-release` green on `main`. This is the **ready-for-tagging** pass:
   `make check-full` as a hard gate, then an advisory ZAP/DAST scan of the live
   host. The DAST step never reddens the command — weigh its findings and, if
   real, file them as an issue (this is how #849 was found) before you tag. It is
   the last moment a finding can hold a release back instead of ending up live.
   Also run `make linux-gate` and glance at open `security`/`privacy` issues.
2. `make catalogs-outdated` — a release carries its bundled reference data for a
   year, so this is the moment to notice upstream moved.
3. `CHANGELOG.md`: turn the `## [0.1.0] — unreleased` heading into the version
   and date you are about to cut.
4. `pubspec.yaml`: `version:` matches the tag.

Then:

```bash
git tag -a v0.1.0 -m "OciDeck 0.1.0" && git push origin v0.1.0
```

### Rehearsing it safely

A tag with a hyphen in it (`v0.1.0-rc1` — a semver pre-release) runs the whole
chain, publishes a release marked **prerelease**, and **skips the live
deployment**. Use that to exercise the pipeline end to end without touching
`ocideck.librekat.nl` or making the download button point at a rehearsal. Delete
the tag and the release afterwards; the real tag then behaves normally.

### The website downloads update themselves

The OciDeck page on **librekat.nl** carries a per-platform download panel
(version, date, size, and the Linux verification hash) pointing at this release's
assets. The `website-downloads` job keeps it current automatically: after
`publiceren`, on the Mac runner, it clones the website repository, runs
`scripts/bump-ocideck.sh <version>` there — which reads the new verification hash
and the release date straight from the published release, so nothing is retyped —
then commits, pushes, and runs `./publiceersite` to put it live. Prereleases are
skipped, and a failure here cannot affect the already-published release: it only
means the site needs the manual fallback, `scripts/bump-ocideck.sh <version>`
followed by `./publiceersite` in the website repository.

The README download line and the librekat.nl download panel themselves were added
when the first release (`0.1.0`) existed; nothing one-time is left here.

### The two secrets it needs

Release publication itself needs nothing: Forgejo injects a per-run token that
may create releases (verified — `POST /releases` returns 201). Should a future
Forgejo version narrow that, set a repository secret `RELEASE_TOKEN` and the
workflow prefers it.

Putting the web build live **does** need credentials, and they are repository
secrets on the forge — see
[HOSTING.md](HOSTING.md#automatic-deployment-on-a-tag) for how to create them:

- `DEPLOY_SSH_KEY` — private half of a deploy key for the static host;
- `DEPLOY_KNOWN_HOSTS` — that host's public key, pinned in advance. The workflow
  refuses to run `ssh-keyscan`: trusting whatever key answers is the assumption
  a man-in-the-middle needs.

Without them the `deploy-web` job **skips** the live step — it does not fail, so
a tag produces no red job and no failure mail. The skip now writes a visible
`⏭️ Web NIET live gezet` note to the run summary, so a green `deploy-web` job is
not mistaken for "the web is live" (#1169). The release still publishes, because
the desktop downloads do not depend on the web host; put the web version live by
hand with `make deploy-web` (which now builds the bundle first, so it no longer
fails on a missing `build/web/` after a `flutter clean`). Set both secrets to
have a tag deploy the web automatically again.

### Signing the macOS release on the runner (one-time)

The `macos` job signs and notarises on `mac-brenno` using items already in that
Mac's **login keychain** — nothing is exported into repository secrets, and the
certificate never leaves the machine. Set it up once on the runner:

1. **Developer ID certificate** — Xcode → *Settings → Accounts → Manage
   Certificates → + → Developer ID Application*. Confirm with
   `security find-identity -v -p codesigning`.
2. **notarytool profile** `ocideck-notary`, stored in the **file-based login
   keychain** — the `--keychain` flag is mandatory. Without it `notarytool` saves
   into the session-bound data-protection keychain, which vanishes after a runner
   restart; that is exactly what failed the first rehearsal (`v0.1.3-rc1`).

   ```sh
   xcrun notarytool store-credentials \
     --keychain "$HOME/Library/Keychains/login.keychain-db" ocideck-notary \
     --apple-id "<apple-id>" --team-id <TEAMID>
   ```

3. **Release the signing key for non-interactive use.** The runner is a
   LaunchAgent with no terminal, so without this codesign blocks on a keychain
   dialog no one is there to answer:

   ```sh
   security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
     ~/Library/Keychains/login.keychain-db
   # enter the login password when prompted — do not put it on the command line
   ```

Rehearse before trusting it: push a pre-release tag (`v0.1.3-rc1`) — it runs the
whole chain, publishes a **prerelease**, and skips the live web deploy (see
[Rehearsing it safely](#rehearsing-it-safely)). Watch the `macos` job sign and
notarise, then delete the tag and the rehearsal release.

### Signing status of the published artifacts

The macOS `.app` is signed and notarised **by the release workflow itself**: the
`macos` job runs `scripts/notarize_macos.sh` when a Developer ID identity is
present on the runner, and falls back to an ad-hoc build with a loud warning when
it is not — so a misconfigured runner can never quietly ship something everyone
assumes is signed. See the one-time setup above.

Windows and Linux are **not** signed, so Windows shows a SmartScreen warning.
`.forgejo/release-body.md` carries the per-platform open instructions; trim a
platform's note only once its published artifact is actually signed (macOS once a
tag has been seen producing a notarised `.app`). `SHA256SUMS` itself proves only
that you have the bytes that were published; *who* published them is attested
separately, by a minisign signature over that list — see *Signing the release
manifest* below.

**Windows signing was assessed and deliberately declined** (#1013, closed
2026-07-31), so "not signed" here is a decision, not a to-do. Two facts drove it.
Since March 2024 neither an OV nor an EV certificate grants instant SmartScreen
trust — reputation accrues only with download volume — so signing would not
silence the warning up front. And every publicly-trusted signing key must now
live on a hardware token or a cloud-HSM, which for CI means a signing secret in
the release runner, against this project's least-privilege line. The chosen
posture is `SHA256SUMS` plus the source route as the provenance guarantee. The
re-open trigger is recorded with the decision: if the warning ever becomes a real
barrier, sign with an OV certificate by hand on a local machine (the
macOS-notarisation model), not from CI. Linux artifact signing (#1014) is
handled a level up — by a detached signature over the whole `SHA256SUMS` manifest
rather than a per-binary certificate; see *Signing the release manifest* below.
The full reasoning lives in
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md#releases-are-alpha-and-unsigned) and
[SECURITY.md](../SECURITY.md#release-artifact-integrity-and-signing).

#### Signing the release manifest (minisign)

The release manifest `SHA256SUMS` carries a minisign detached signature
`SHA256SUMS.minisig`. Because the manifest lists every artifact's checksum, one
signature over it anchors the whole release — Windows, Linux and the SBOMs
included — without a per-binary certificate. This is the answer to #1014, and it
is done **by hand, locally**, so the signing key never becomes a runner secret.
minisign is chosen over GPG for the same reason SSH is chosen over GPG for commit
signing ([GIT_STORAGE.md](design/GIT_STORAGE.md)): it signs one small Ed25519 file
with no keyring and no web-of-trust, and it has several compatible
implementations.

One-time setup:

```sh
brew install minisign            # macOS; Debian/Ubuntu: sudo apt install minisign
minisign -G -p minisign.pub -s ~/.minisign/ocideck-release.key
```

Commit the public half (`minisign.pub`) to the repository root; keep the private
half (`~/.minisign/ocideck-release.key`) local and never commit it — `.gitignore`
guards the filename as a backstop. A password on the private key is **strongly
recommended** — this key is a release root of trust, so one that can be read
straight off disk lets anything that reads `~/.minisign/` forge signatures until
the key is rotated. Add one with
`minisign -C -s ~/.minisign/ocideck-release.key`; `make sign-release` then prompts
for it at signing time.

Per release, after the workflow has published the tag:

1. Download `SHA256SUMS` from the published release into a working directory.
2. `make sign-release SHA256SUMS=path/to/SHA256SUMS` (or run it where
   `dist/SHA256SUMS` sits). The script signs and immediately verifies against
   `minisign.pub`, refusing to leave a signature it cannot verify.
3. Attach the resulting `SHA256SUMS.minisig` to the release, beside `SHA256SUMS`.

A recipient verifies with `minisign -Vm SHA256SUMS -p minisign.pub`.
`OCIDECK_RELEASE_KEY` overrides the key path for a different signer.

##### Backing up and escrowing the key

The private key is a single point of failure, and losing it is not hypothetical:
`v0.2.0` nearly shipped unsigned because the passphrase had been forgotten (it was
recovered). Two things keep that from becoming a real loss, and both are manual —
they are deliberately **not** automated, because the whole point is that the key
and its passphrase never touch a runner or the repository:

- **Passphrase in a password manager**, not only in someone's memory. It is the
  key to a release root of trust; treat it like one.
- **An offline backup of the private key file** (`~/.minisign/ocideck-release.key`)
  on a second secure medium — an encrypted volume or another machine's protected
  keystore. Never in the repository (`.gitignore` guards the filename as a
  backstop, and `release_signing_test.dart` fails the build if `minisign.key` or
  `ocideck-release.key` ever appears in the tree) and never as a runner secret.

The public half is safe to copy anywhere; it is already in the repository and on
the mirror.

##### Rotating the key

Rotate when the private key or its passphrase is lost, when the key may have been
exposed, or on a planned schedule. Because releases from `v0.2.0` onward are
signed, a rotation is a **published event**, not a silent swap: a receiver
cross-checks the key ID out of band, so a quiet replacement is indistinguishable
from an attacker swapping the key. Steps:

1. **Generate a fresh keypair** (new passphrase, stored in the manager). `-f`
   overwrites the retired files and writes the new public key straight into the
   repository root:

   ```sh
   minisign -G -f -p minisign.pub -s ~/.minisign/ocideck-release.key
   ```

2. **Update every pinned copy of the public key / key ID.** The build fails until
   they all agree — that is `test/release_signing_test.dart` doing its job, not a
   nuisance. Read the new key ID from line 1 of the fresh `minisign.pub`
   (`untrusted comment: minisign public key <ID>`) and the new base64 from line 2,
   then fix the four places:

   | File | What to change |
   | --- | --- |
   | `minisign.pub` (repo root) | already written by step 1 |
   | `test/release_signing_test.dart` | `verwachteSleutel` (the base64 line) **and** `verwachteSleutelId` |
   | `SECURITY.md` | the key ID in *Release artifact integrity and signing* |
   | `.forgejo/release-body.md` | the key ID in the verify blurb shipped in every release body |

3. **Prove they agree:** `flutter test test/release_signing_test.dart` must pass
   (it checks the pin, that the private key did not leak into the tree, and that
   the four references line up).

4. **Land it via PR before the next tag**, and **announce it in `SECURITY.md`**
   with a dated note: the old key ID is retired, the new one is `<ID>`, effective
   from release `vN`. That note is the out-of-band signal that makes the new key
   trustworthy — put it where receivers already look (the repo, the mirror,
   `SECURITY.md`). Releases signed with the old key stay verifiable against the
   `minisign.pub` committed *at their own tag*; new releases verify against the new
   key.

##### A reserve key turns a forced rotation into a planned one (recommended)

Generate a second keypair offline once, and decide up front how it backs up the
primary — so a lost or exposed key points at something already trusted instead of
introducing a brand-new key under pressure:

- **Document-only (cheap, covers "key lost").** List the reserve public key and
  its ID in `SECURITY.md` as *the key we will rotate to*. Receivers can trust it
  in advance, so a rotation is only steps 2–4 above with values that were already
  published.
- **Co-sign (covers "primary key compromised", but doubles the signing step).**
  Attach a second detached signature from the reserve key
  (`SHA256SUMS.reserve.minisig`) to each release, so forging a release means
  forging *both*. Keep the reserve private key on different media than the primary.

Either way the reserve private key lives offline and never on a runner, same as
the primary.
