# OciDeck — Build & Release

How to build OciDeck from source and produce distributable apps.

## Prerequisites

- **Flutter 3.44.6** (stable) / **Dart 3.12.2** — the exact version CI pins
  (see `.tool-versions` and both `.github/workflows/*.yml`). Building tolerates
  3.44+, but **`make format-check` is version-sensitive**: a different
  `dart format` reflows whitespace and fails the gate. Use the Flutter-bundled
  `dart` (not a separately installed standalone Dart, which can drift) so
  `make format-check` stays reproducible across machines. Check with
  `flutter --version`.
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

### Response headers the host must add

The CSP in `web/index.html` is delivered via a `<meta>` tag, which covers most
directives — but browsers **ignore `frame-ancestors` (and `sandbox`/`report-*`)
when they arrive via `<meta>`**. To actually prevent clickjacking, the static
host must send these as HTTP **response headers** for the app's HTML:

```
Content-Security-Policy: frame-ancestors 'none'
X-Frame-Options: DENY
```

(When embedding the bundle inside Nextcloud, replace `'none'` with the host
origin instead of dropping the header.) Ideally serve the **entire** CSP as a
response header rather than relying on the meta tag. Example snippets:

- **nginx**: `add_header Content-Security-Policy "frame-ancestors 'none'" always; add_header X-Frame-Options "DENY" always;`
- **Caddy**: `header Content-Security-Policy "frame-ancestors 'none'"` and `header X-Frame-Options "DENY"`
- **Apache**: `Header always set X-Frame-Options "DENY"` and `Header always set Content-Security-Policy "frame-ancestors 'none'"`

> A plain `flutter build web` still works, but it falls back to the gstatic CDN
> and an `unsafe-*` loader — use `make build-web` so the hardening stays pinned.

### Deeplink: app + presentatie in één URL

`https://<host>/?deck=<url>` opent OciDeck én haalt direct de presentatie op
het meegegeven adres op (URL-encoderen!). Dezelfde importpoort geldt als bij
"Importeren via URL": veiligheidsscan, marp-controle en de CORS-regels
hieronder. Voorbeeld:

```
https://ocideck.librekat.nl/?deck=https%3A%2F%2Fexample.org%2Fdeck.ocideck
```

### Fetch-hulppunt voor URL-import (optioneel, aanbevolen)

"Importeren via URL" werkt in de browser alleen direct voor bronnen die CORS
toestaan. Om een deck van **elke** URL te kunnen openen, deploy je naast de
statische bundel het SSRF-bewaakte fetch-hulppunt: zie
[`server/fetch-proxy/README.md`](../server/fetch-proxy/README.md). De webapp
valt automatisch terug op het same-origin pad `/fetch-proxy?url=…`; zonder
hulppunt blijft alles werken en legt de foutmelding de CORS-beperking uit.

## Quality gate

```sh
make check        # format-check + flutter analyze + full test suite
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

## CI

> **The CI workflows are defined but do not currently run.** The remote is a
> Forgejo instance with no runner configured, so nothing fires on push or tag.
> `make check` (and `make check-full`), run by the committer, is the enforced
> gate; release bundles must be built manually on each target OS. See
> [CHECKS.md](CHECKS.md#continuous-integration).

`.github/workflows/ci.yml` *declares* the quality gate on Ubuntu for every push
and pull request (plus `flutter test` on macOS and Windows). It does not build
native binaries; it validates formatting, static analysis, and the test suite
(which are platform-independent).

`.github/workflows/release.yml` *declares* the distributable-artifact build. On a
version tag (`v*`) — or a manual run — it would build **web, macOS, Windows and
Linux** on their matching runners and upload each as an artifact, so one tag
produces all four. Both workflows pin **Flutter 3.44.6** (stable).

For the full check reference, see [`CHECKS.md`](CHECKS.md).
