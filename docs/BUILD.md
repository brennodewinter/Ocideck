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

- **Flutter 3.44.7** (stable) — the exact version CI pins (see `.tool-versions`
  and both `.github/workflows/*.yml`). Only Flutter is pinned; the Dart SDK comes
  bundled with it, and `pubspec.yaml` merely constrains it (`sdk: ^3.12.0`).
  Building tolerates
  3.44+, but **`make format-check` is version-sensitive**: a different
  `dart format` reflows whitespace and fails the gate. Use the Flutter-bundled
  `dart` (not a separately installed standalone Dart, which can drift) so
  `make format-check` stays reproducible across machines. Check with
  `flutter --version`.

  In short: *build* with 3.44 or newer if you must, but *pass the gate* with
  3.44.7. The two are different requirements and only the second is enforced.
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
there, and OciDeck has neither today. Signed artefacts (Authenticode,
notarisation, a detached signature) are a desktop-release concern and are not
part of the web-only 0.1.0. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

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
- **Apache**: `Header always set X-Frame-Options "DENY"`, `Header always set Content-Security-Policy "frame-ancestors 'none'"` and `Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"`

See [`HOSTING.md`](HOSTING.md) §3 for what `preload` would additionally commit
you to, and why it is not the default recommendation.

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
make build-web       # hardened web bundle              → build/web
make build-all       # web + this machine's native desktop target
```

Use `make build-release` for the normal manual release path on macOS. It runs
`make check-web` first, so the browser bundle is built with
`--no-web-resources-cdn --csp` and then verified for the strict CSP,
self-hosted CanvasKit, and bundled UI font before the macOS app is built.

`make build-all` builds the web bundle plus whichever desktop target matches the
host OS (web + macOS on a Mac, web + Linux on Linux). A desktop bundle cannot be
cross-compiled, so a bundle for another OS must be built on that OS (the release
workflow in `.github/workflows/release.yml` would do this across runners, but it
does not currently run — see the [CI](#ci) note). Artifacts land under
`build/<platform>/`.

### macOS notes

- **Swift Package Manager is disabled** for this project (`flutter:` →
  `config: enable-swift-package-manager: false` in `pubspec.yaml`); CocoaPods is
  used instead. The "plugin does not support Swift Package Manager" message
  during a build is therefore expected and harmless.
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

- **Distribution**: code-sign and notarize the `.app` for distribution outside
  the App Store (Developer ID + `notarytool`). This is environment-specific and
  not automated here.

### Windows / Linux notes

- Windows: distribute the contents of `build/windows/x64/runner/Release/` (or
  package with MSIX/an installer).
- **Windows-bestandsassociaties**: importeer
  [`windows/file-associations.reg`](../windows/file-associations.reg) (paden
  aanpassen) of neem de sleutels op in de installer. `.ocideck` opent dan
  direct met OciDeck; `.md` krijgt OciDeck als "Openen met…"-optie zonder de
  standaard over te nemen. De app opent het meegegeven pad bij het starten.
  macOS regelt hetzelfde via `CFBundleDocumentTypes` in `Info.plist`
  (`.ocideck` = Owner, `.md` = Alternate) — dat zit al in de app-bundel.
- Linux: distribute `build/linux/x64/release/bundle/` (or package as a
  Flatpak/AppImage/Snap as you prefer).

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

> **Since 2026-07-23 the forge has an Actions runner.** The quality gate
> (`make check`) runs in CI **on a `v*` tag** (`.forgejo/workflows/ci.yml`,
> #751/#790) — not per pull request. A gate run cost 22 minutes on that runner
> against 2.5 minutes locally, and that wait per PR did not earn its keep next
> to a `make check` every committer already runs before pushing. The honest
> consequence: CI is no longer a merge gate but a **release** gate. If it fails
> on a tag, the problem is already on `main`, and the assurance before `main`
> is entirely the committer's local run. The gate caches the pinned Flutter
> toolchain and the pub packages (#790); that removes repeated download and
> extraction work, not a check — `check-toolchain` still runs inside
> `make check` on the restored tree and still demands channel `stable`, the
> official origin, and equality with the pin.
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

`.github/workflows/release.yml` *declares* the distributable-artifact build. On a
version tag (`v*`) — or a manual run — it would build **web, macOS, Windows and
Linux** on their matching runners and upload each as an artifact, so one tag
produces all four. Both workflows pin **Flutter 3.44.7** (stable).

For the full check reference, see [`CHECKS.md`](CHECKS.md).
