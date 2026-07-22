# Security Policy

This policy covers vulnerabilities in **OciDeck itself** (the application). It does
**not** govern how findings from a penetration test authored *with* OciDeck are
disclosed — that is arranged per engagement with the client (scope, reporting
channel, and disclosure terms), not dictated by this tool.

The mailbox below is the project's only published address, so it also receives
Code-of-Conduct reports, which follow [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
rather than this policy. *(Noted 2026-07-22: the scope sentence above admits only
vulnerabilities, which made the shared use of the address look like a mistake.)*

## Reporting a vulnerability

**Please do not report security vulnerabilities through public issues, pull
requests, or other public channels.**

Instead, report them privately by e-mail to **security@librekat.nl**, and wait for
a reply before disclosing anything publicly. There is no published PGP key, so a
report arrives as ordinary e-mail; if that is unacceptable for what you have
found, send a first message without the details and we will agree on a channel.
*(Corrected 2026-07-21: this paragraph used to ask you to "encrypt the report if
you can" — an instruction nobody can follow, because no key is published.)*

You will receive an acknowledgement (see [What to expect](#what-to-expect)); if you
do not hear back within a few working days, please send a reminder to the same
address.

When reporting, please include as much of the following as you can:

- A description of the issue and its impact.
- Steps to reproduce (a minimal deck or input file if relevant).
- The commit you built from, your operating system, and the Flutter version.
  (There is no released version to quote, and the app does not display a version
  of its own — see [Supported versions](#supported-versions).)
- Any proof-of-concept, logs, or screenshots.

## What to expect

- **Acknowledgement** of your report as quickly as we reasonably can.
- An assessment and, where confirmed, a fix developed under coordinated
  (responsible) disclosure.
- Credit for the discovery if you wish — let us know how you would like to be
  named.

We ask that you give us a reasonable opportunity to address the issue before any
public disclosure, and that you avoid privacy violations, data destruction, or
service disruption while researching.

## Scope notes

OciDeck runs entirely on the machine in front of you — as a desktop app, or
wholly inside a browser tab. Areas of particular interest:

- Parsing of untrusted decks (`.md`), packages (`.ocideck`), style profiles
  (`.ocideckstyle`), sidecars (`.ink.json`, captions), and linked CSV data.
- Importing presentations from a URL.
- The **network deck sources** — user-configured servers the app authenticates
  to and reads or writes decks on, including how each one's credentials are
  stored and how its host is reached (see below). There are three, and all
  three are in scope:
  - **Nextcloud/WebDAV** (basic auth);
  - **S3** — AWS S3 or any S3-compatible endpoint (MinIO, Ceph, Wasabi), signed
    with a hand-written SigV4 rather than the AWS SDK;
  - **Git** — a forge over REST (Gitea/Forgejo, GitHub, GitLab) *and* a native
    `git` subprocess. That subprocess is the one outbound path where the socket
    is not ours to pin, which makes it the most interesting of the three.
- The HTML export, which inlines third-party JavaScript (marked, highlight.js,
  mermaid, MathJax) to render offline.
- The export classification gate (`ClassificationPolicy`) — any way to export a
  deck classified above the configured release ceiling.
- The **web build's self-contained guarantee.** Built with `make build-web`, the
  browser app bundles CanvasKit and the UI font locally (no gstatic CDN) and runs
  under a strict Content-Security-Policy in `web/index.html` (`script-src 'self'
  'wasm-unsafe-eval'`, no `unsafe-inline`/`unsafe-eval`; media first-party). Any
  way to make the running app load third-party script or origins is in scope.

### Vendored bundle currency

`make deps-check` queries OSV for every pinned bundle in
`assets/web_export/MANIFEST.json`; it is part of `make check-full`, which the
committer runs before a dependency or web-facing change (the CI workflow that
also declares it does not currently run — the remote is Forgejo with no runner).
As of the last review all
pins (marked 18.0.5, highlight.js 11.11.1, DOMPurify 3.4.11, mermaid 10.9.6,
MathJax 3.2.2) carry **no known advisories**. Two tracked (non-urgent)
maintenance items:

- **mermaid 10.9.6 → 11.x** is a planned major upgrade, deferred until its
  rendering can be validated (real offscreen WebView), as it fixes no known
  advisory. Note mermaid bundles its **own** DOMPurify (3.4.2) internally,
  independent of the pinned 3.4.11; a DOMPurify advisory is only caught via the
  `mermaid@version` OSV query. This is mitigated in depth: mermaid runs with
  `securityLevel: 'strict'` and `htmlLabels: false`, its SVG output is run
  through `sanitizeMermaidSvg` and then the pinned DOMPurify (SVG profile).
- **MathJax 3.2.2** — the only report against it is a disputed ReDoS
  (CVE-2023-39663), impact bounded to DoS on crafted TeX; upgrade tracked.

### Software Bill of Materials

OciDeck carries a machine-readable **SBOM** in both common formats — CycloneDX 1.6
(`sbom/ocideck.cdx.json`) and SPDX 2.3 (`sbom/ocideck.spdx.json`) — listing every
component: Dart/Flutter packages direct and transitive, vendored JS/CSS bundles,
plugin forks, fonts, and the build SDKs, each with version, purl and licence. It
is generated by `make sbom` and kept current by the `make sbom-verify` staleness
gate in the test suite (`make check`).

Two boundaries, because both were overstated here before (*corrected
2026-07-21*):

- **SHA-256 covers most components, not all.** Of the 199 components listed, 190
  carry a hash. The nine that do not are the two vendored plugin forks under
  `third_party/` (`desktop_multi_window`, `screen_retriever_macos`), the
  packages that ship inside the Flutter SDK rather than from pub, and the SDKs
  themselves — none of which has a pub archive hash to record.
- **It travels with the web build only.** `make build-web` copies `sbom/` into
  `build/web/sbom/`, so a hosted instance serves it from its own origin. The
  desktop build recipes do not bundle it; there, the SBOM lives in the
  repository and nowhere else.

It feeds external vulnerability scanners (Dependency-Track, `osv-scanner`) for
the Dart/Flutter graph. See [`docs/SBOM.md`](docs/SBOM.md).

## Untrusted deck handling

A `.md` deck (and the assets it references) may come from an untrusted source.
OciDeck constrains what an opened deck can do:

- **Asset-path containment.** Image / video / audio / logo / chart paths in a
  deck are resolved strictly inside the deck's project folder. Absolute paths
  and `../` escapes are ignored by the preview, presenter, exporter, the
  slide-quality analyzer (so a crafted deck can't turn the "missing media" check
  into a file-existence oracle), and the copy-to-clipboard action — all via
  `resolveSlideAssetPath` in `lib/utils/project_path.dart`. The in-editor image
  *display* is intentionally permissive (so a user can preview a freshly picked
  image before it is copied into the project), but it is never used as a read
  sink for clipboard or export.
- **Size limits.** A deck `.md` is capped at 32 MiB on open; `.ocideck`
  packages at 512 MiB / 10 000 entries with zip-slip and decompression-bomb
  guards; a `.ocideckstyle` style profile at 16 MiB with its embedded logo at
  8 MiB; URL imports use an `http`/`https` allowlist with an SSRF host
  blocklist and no redirect following.
- **Style profiles are validated, not trusted.** A profile carries colours and
  font names that are interpolated into a `<style>` block on export, so an
  unvalidated value like `red}</style>…<style>` would be a CSS/HTML injection.
  Every profile — whether it arrives inlined in a deck's front matter or as a
  standalone `.ocideckstyle` — passes through the single hardened gate
  `ThemeProfile.fromJson`, which validates each colour to a strict `#RRGGBB`
  literal and whitelists font families against the offered set, falling back to
  the default for anything else. This matters because the import-safety scanner
  never sees the base64 front-matter payload. An embedded logo is accepted only
  after a magic-byte check (its declared MIME type is ignored and re-derived
  from the bytes), and a profile that carries a bare `logoPath` without an
  embedded image has that path dropped rather than resolved.
- **Render/export sanitization.** Deck content rendered to HTML is sanitized
  with the bundled DOMPurify before insertion into the DOM, and the export
  carries a **nonce-based Content-Security-Policy** (`script-src 'nonce-…';
  object-src 'none'; base-uri 'none'`) so an injected inline script that somehow
  survives sanitization still can't execute when the file is opened. Mermaid in
  the export runs `securityLevel:'strict'` and its produced SVG is re-sanitized
  with DOMPurify; the in-app mermaid render webview is locked down with its own
  CSP.
- **Bounded image decoding.** Every deck-supplied image is decoded with its
  dimensions capped (`cappedFileImage` / `kMaxImageDecodeDimension`), so a
  small but huge-dimensioned file can't exhaust memory on display or export.
- **SSRF — hostname resolution + socket pinning.** URL import resolves the host
  up front, rejects it if *any* resolved address is internal (loopback /
  private / link-local / metadata), and then **pins the connection to that
  validated address** (`connectionFactory`), so a DNS rebind between the check
  and the connect can't redirect the socket internally. TLS still validates
  against the original hostname.
- **WebDAV/Nextcloud source — credentials and trust boundary.** The app
  password is stored encrypted in the OS keychain (`flutter_secure_storage`,
  keyed by server URL + username via `SecretStore`), never in the preferences
  file; only the server URL, username, subfolder and trust flag live in prefs.
  The configured server is the only host allowed to bypass the private-address
  SSRF block, and only after the user explicitly ticks **Trusted internal
  server** (`NetGuard.safeResolveTrusted`); the host is still resolved and the
  socket pinned, and deck-supplied URLs never get this exception. WebDAV
  requests follow no redirects, cap the PROPFIND response and entry count, and
  enforce the same per-file size limits as other imports; remote paths are
  contained to the configured root (`WebdavServer.uriFor` rejects `..` escapes)
  and listing entries with a traversal segment are dropped. Downloaded decks go
  through the same `MarkdownSafetyScanner` gate and `.ocideck`/`.md` limits as
  every other import.
- **S3 source — credentials, signing and trust boundary.** The **secret** access
  key is stored in the OS keychain (`SecretStore`); the endpoint, bucket, region
  and the **access key ID** stay in prefs. The key ID is an identifier rather
  than a password, but it names the account to anyone who reads that file.
  Requests are signed by a hand-written SigV4 (`lib/services/s3/s3_sigv4.dart`)
  rather than by the AWS SDK, deliberately: an SDK brings its own HTTP stack and
  would connect *around* `NetGuard`, and the algorithm is small enough to test
  against AWS's own vectors (`test/s3_sigv4_test.dart`). Plain `http` is refused
  unless the bucket is ticked **Trusted internal** (the MinIO-on-the-LAN case),
  which is also the only thing that lifts the private-address block; the host is
  still resolved and the socket pinned exactly as for WebDAV. Requests follow no
  redirects (a 3xx must not walk around the host check), downloads are capped
  both by `Content-Length` pre-check and by streaming cap, listings are capped
  in entry count across all pages taken together, and object keys are contained
  to the configured root prefix — `S3Bucket.keyFor` returns null on a `..`
  escape, including an escape out of the bucket when no prefix is configured.
- **Git source — a token that leaves the keychain, and a socket that isn't
  ours.** The personal-access token is stored in the OS keychain; base URL,
  owner, repo and trust flag are prefs. Two transports carry it. The REST path
  (Gitea/Forgejo, GitHub, GitLab) is an ordinary `HttpClient` under the same
  resolve-and-pin as WebDAV and S3. The **native path** is a `git` subprocess,
  and there no `connectionFactory` of ours exists to hook into: git does its own
  DNS and opens its own socket. So the guard is *imposed* on it instead —
  `http.curloptResolve` binds the hostname to the address `NetGuard` approved
  (TLS still validates against the name, so no certificate has to name an IP),
  and `http.followRedirects=false` turns a redirect into an error rather than a
  second host nobody vetted. The second matters more here than elsewhere: the
  token travels as an `http.extraHeader`, and a header follows a redirect — a
  remote answering 302 would otherwise be handed the `Authorization`. Config
  reaches git through `GIT_CONFIG_*` environment variables, so the token lands
  in neither argv, nor the remote URL, nor `.git/config`. The process starts
  with `includeParentEnvironment: false` and an **allowlisted** environment:
  only what a process needs in order to run, plus `GIT_TERMINAL_PROMPT=0`,
  `GIT_CONFIG_NOSYSTEM=1`, a `GIT_CONFIG_GLOBAL` pointed at `/dev/null` and a
  controlled empty `HOME` — so no `~/.gitconfig`, credential cache or alias
  reaches it, and neither does a `GIT_TRACE_CURL`, `GIT_ASKPASS` or
  `GIT_CONFIG_PARAMETERS` that happened to sit in the user's shell. Residual, and
  stated plainly: for the lifetime of that process the token exists outside the
  keychain. That the imposition is real and not paper is asserted against a live
  server in `test/git_network_guard_test.dart`.
- **Symlink containment.** Both the copy-to-clipboard sink
  (`resolveContainedRealPath`) and the render/export path (`isRenderPathContained`,
  cached so the per-frame cost is O(1)) resolve the real (symlink-followed)
  path and refuse a project-internal symlink that escapes the project. Package
  import already skips symlink entries.
- **Per-asset import validation.** Picked/pasted images are validated by magic
  bytes (PNG/JPEG/GIF/BMP/WebP), not just the file extension, and capped at
  64 MiB; video/audio imports are capped at 1 GiB.
- **Online media is gated and fails closed.** Image/video URLs and YouTube/Vimeo
  embeds are only fetched live when the **Online media** setting is on (off by
  default), so an opened deck authored by someone else cannot beacon home or
  pull third-party content unasked. At insert time URLs pass the same
  `http(s)`-only + SSRF host blocklist (`NetGuard`, shared with URL import).
  Live rendering (`NetworkImage` / `VideoPlayerController.networkUrl` / the embed
  WebView) does its own DNS, so it cannot pin the socket the way URL *import*
  does — this residual SSRF/rebind exposure is the reason the gate defaults off
  and is scoped to user-enabled sessions. The connect-time media check
  (`NetGuard.isAllowedMediaUrlResolved`) also **caches a positive host
  resolution for the session**, so a host that resolved externally once is not
  re-validated later in that session; this is an accepted trade-off for the
  higher-level Flutter media APIs, whereas the URL *import* path avoids it by
  pinning the socket to the validated address. Remote images keep the decode-dimension
  cap (`cappedNetworkImage`); magic-byte validation does not apply to live
  streams (no pre-fetched bytes), a deliberate trade-off. The embed WebView
  restricts navigation to the player origins and refuses auth prompts/pop-ups.

Known residual hardening: the render-path symlink cache is keyed by path for the
session, so a symlink swapped *after* its first render isn't re-checked (a
narrow TOCTOU on an already-open deck).

## Crash-recovery snapshots

Autosave writes each dirty tab's full markdown (and user notes) as **unencrypted
JSON** to `<app-support>/recovery/<uuid>.json`, so work survives a crash. This
means deck content — including a **classified** deck — sits in plaintext on disk
until the tab is saved or discarded. Mitigations: the directory is the
per-user, OS-permissioned app-support path; snapshots are deleted on save and on
"tab became clean"; and orphaned snapshots older than 7 days are pruned on
startup (`RecoveryService.pruneOlderThan`) so a forgotten crash file can't linger
indefinitely. Encrypting these snapshots at rest (keyed via the keychain) is a
known residual improvement, not yet implemented.

A connected **git repository** puts far more than a snapshot there: a native
clone under `<app-support>/git_clone/<storageSlug>/` holds the full deck content
*and its history*, next to a draft store and an outbox of commits not yet
pushed, all unencrypted. The 7-day prune deliberately does not apply — a working
copy is meant to persist. Whatever sensitivity the repository has on the server,
it has on this disk too.

Removing the connection does not remove any of it: `removeConnection` rewrites
the connection list in preferences and stops there, so `git_clone/<slug>/`,
`git_mirror/<slug>/` and the `git_outbox::` keys survive. Deleting them is
manual. *Corrected 2026-07-21: this paragraph used to end "so it stays until the
connection is removed", which implied a cleanup that is not implemented.*

## Platform sandboxing (macOS)

The macOS build currently ships with the App Sandbox **disabled**
(`com.apple.security.app-sandbox = false` in `macos/Runner/*.entitlements`). This
is a deliberate, documented trade-off rather than an oversight:

- OciDeck's desktop file model reads and writes a deck's **sibling asset
  directories** (`images/`, `themes/`, linked CSVs) relative to the opened `.md`,
  and **scans known locations** for decks. Under the sandbox, user selection
  grants access only to the picked item (via security-scoped bookmarks), so both
  flows would break without a substantial redesign toward a folder-picker-only
  model with persisted bookmarks.
- The custom `desktop_multi_window` plugin (dual-screen presenter) and the
  offscreen Mermaid `WebView` would each need their access re-validated under the
  sandbox.

Enabling the sandbox is therefore tracked as a migration, not a one-line
entitlement flip; doing it blindly would silently deny file access. The minimal
target entitlement set, once the file model is bookmark-based, is
`com.apple.security.app-sandbox`, `…network.client` (WebDAV, S3, git),
`…files.user-selected.read-write`, and `…files.downloads.read-write`. Until then,
the app relies on the in-process defences documented above (SSRF guards, import
size/entry caps, path containment, the executable-content scanner) rather than
OS-level process isolation. The `com.apple.security.cs.allow-jit` entitlement in
`DebugProfile.entitlements` is debug-only and is not present in release.

## Supported versions

There is no released version yet. The repository carries no release tag (the one
tag that exists, `archive/git-mirror`, marks an archived branch and is not a
version), `pubspec.yaml` says `0.2.0+1`, and the app does not display a version
number anywhere, so a user cannot read off what they are running. Fixes land on
the default development branch, which is what everyone runs. Once releases are
tagged, fixes will target the latest release plus that branch.
