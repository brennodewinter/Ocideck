# Security Policy

> **Status:** policy, current · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

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
- The version shown under **Settings → Over OciDeck**, the commit you built
  from, your operating system, and the Flutter version. (The version number
  alone does not pin down which commit you ran — see
  [Supported versions](#supported-versions) — the commit hash is what does
  that.)
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

## What happens to your report on our side

This section was added on 2026-07-22 because the one above only described what
you get back, not what is done. It describes the working method, so you can tell
whether your report has fallen through a crack.

**Triage.** A report is first reproduced against the current default branch. If
it cannot be reproduced, you are asked for what is missing rather than told no.
A reproduced report becomes an issue in the tracker — a private one where the
detail would itself be the exploit, public where it would not.

**Severity.** Severity is judged on what an attacker actually gains on the
machine in front of the user, not on the label of the mechanism. The questions
that decide it, in order: can it be reached from a deck or a file a user opens
without any further action; does it cross one of the boundaries this project
exists to hold (the export classification gate, asset-path containment, the
privacy projection boundary, the SSRF guard, the keychain); does it need a
setting that is off by default. The pentest module's own CVSS v4.0 engine is
available for putting a number on it, but the number is a communication aid, not
the decision.

**Ownership.** OciDeck is maintained by a small group under Stichting LibreKAT;
there is no rota and no second line. A report is owned by whoever picks it up,
and that person stays the correspondent until it is closed — so you are not
handed on. If nothing has come back, a reminder to the same address is the right
move; see [Reporting a vulnerability](#reporting-a-vulnerability).

**When the report is about something we bundle, not something we wrote.** That is
a large part of the attack surface: five vendored JavaScript bundles in the HTML
export, the Dart/Flutter package graph, two plugin forks, and the offline
reference datasets. The report is still handled here, because a user runs what
we ship regardless of who wrote it. What changes is the fix: an upstream
advisory is answered by moving the pin and refreshing
`assets/web_export/MANIFEST.json`, not by patching a vendored copy — a local
patch is invisible to `make deps-check` and to every external scanner reading the
SBOM. Where no upgrade is available, the mitigation and the residual are written
down in [Vendored bundle currency](#vendored-bundle-currency) under the
component's own name, so a reader can see it rather than infer it.

## Keeping vulnerable third-party components out

**This describes how the maintainers order their own work. It is not a service
commitment, and no timeframe here is promised to anyone.** OciDeck is an
open-source project with an alpha release process (see [Supported
versions](#supported-versions)); a fixed remediation deadline is exactly the kind
of promise that becomes untrue the first quiet month. What follows is the
steering instrument, written down so it can be held to in behaviour.

**What is a gate and what is advice**, because the difference decides how fast
something has to move:

| Check | Fails the work? | Covers |
| --- | --- | --- |
| `make deps-check` | **Yes** — part of `make check-full` | The five vendored export bundles: SHA-256 against the manifest, plus an OSV query per pinned version. Also the bundled reference standards against upstream. |
| `make sbom-verify` | **Yes** — in the test suite | The committed SBOM still matches the dependency set. |
| `make trivy` | **No, by configuration** | CVEs in the resolved Dart packages, plus a committed-secret sweep. [`trivy.yaml`](trivy.yaml) says so itself: it reports every severity and never fails the build, because Dart/pub advisory coverage is sparse enough that a gate would mostly teach people to skip it. Findings are triaged by hand. |
| `make deps-outdated`, `make catalogs-outdated` | **No** | Freshness of packages and of the bundled standards. A newer upstream is not a defect in what you built. |

**The rhythm.** `make check-full` — which is where the gates above live — is run
before any dependency or web-facing change, and before a build meant for anyone
else. There is no scheduled scan, because there is no runner to schedule it on:
the Forgejo remote has none, so the CI workflow that declares these checks is
written but never fires. Whoever commits is the scan.

**How urgency is decided.** In descending order, and this is the whole of it:

1. A component that untrusted deck content or a network response can reach
   *without* a setting being turned on — the sanitiser, the parsers, the export
   bundles — moves ahead of whatever else was planned.
2. A component reachable only behind an off-by-default switch (the AI backend,
   the CVE lookup, online media) is upgraded on the ordinary rhythm, and the
   exposure is named in this file meanwhile.
3. An advisory that is disputed, or whose worst case is denial of service on
   input the user chose to open, is tracked by name and version rather than
   rushed — as `CVE-2023-39663` against MathJax 3.2.2 is below.
4. An upgrade with no advisory behind it waits until its behaviour can be
   validated, and the reason for waiting is written down — as the mermaid 10 → 11
   upgrade is below.

The point of writing the order down is that the third and fourth categories are
where a project quietly stops looking. Naming a deferred item, with its version
and its reason, is what keeps it from becoming a decision nobody remembers
taking.

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
pins (marked 18.0.5, highlight.js 11.11.1, DOMPurify 3.4.12, mermaid 11.16.0,
MathJax 3.2.2) carry **no known advisories**. One tracked (non-urgent)
maintenance item:

- **MathJax 3.2.2** — the only report against it is a disputed ReDoS
  (CVE-2023-39663), impact bounded to DoS on crafted TeX; upgrade tracked.

*(Corrected 2026-07-22: this section carried two contradicting opening
paragraphs — one saying every pin was clean, the next saying DOMPurify 3.4.11
carried an advisory and naming mermaid 10.9.6 — followed by a count that
matched neither list. The second was left behind by the DOMPurify upgrade:
`assets/web_export/MANIFEST.json` pins 3.4.12 and mermaid 11.16.0, and the
checked-in bundles hash to those. So the document was reporting a
vulnerability in a version this project does not ship.)*

Note that mermaid bundles its **own** DOMPurify internally, independent of the
pinned one; a DOMPurify advisory is therefore only caught via the
`mermaid@version` OSV query. This is mitigated in depth: mermaid runs with
`securityLevel: 'strict'` and `htmlLabels: false`, its SVG output is run through
`sanitizeMermaidSvg` and then the pinned DOMPurify (SVG profile).

### Software Bill of Materials

OciDeck carries a machine-readable **SBOM** in both common formats — CycloneDX 1.6
(`sbom/ocideck.cdx.json`) and SPDX 2.3 (`sbom/ocideck.spdx.json`) — listing every
component: Dart/Flutter packages direct and transitive, vendored JS/CSS bundles,
plugin forks, fonts, and the build SDKs, each with version, purl and licence. It
is generated by `make sbom` and kept current by the `make sbom-verify` staleness
gate in the test suite (`make check`).

Two boundaries, because both were overstated here before (*corrected
2026-07-21*):

- **SHA-256 covers most components, not all.** Of the 199 components listed, 192
  carry a hash. The seven that do not are the packages that ship inside the
  Flutter SDK rather than from pub (`flutter`, `flutter_localizations`,
  `flutter_test`, `flutter_web_plugins`, `sky_engine`) and the two build SDKs
  themselves — none of which has a pub archive hash to record. The two vendored
  plugin forks under `third_party/` used to be in this list; since 2026-07-22
  they carry a **tree hash** (SHA-256 over the sorted per-file digests of the
  vendored directory) plus the upstream commit they were branched from, so what
  we ship is verifiable even though a path dependency has no archive.
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
- **The scanner's own-identity allowlist.** *Settings → Security → Your own
  details* holds the user's name, e-mail address, phone number and organisation
  domain so the privacy scanner does not report the sender as a finding. It is
  not a credential, but it is the only preference carrying personal data about a
  natural person, so it lives in the keychain
  (`SecretStore.privacyOwnIdentityKey`) rather than in the preferences file.
  Migration order matters and is deliberate: the legacy `privacyOwnIdentity`
  preference is removed only once the keychain has accepted the value, because
  losing the allowlist makes the scanner start flagging the user's own name —
  the single largest false-positive source there is.
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
  restricts navigation to the player origins and refuses auth prompts/pop-ups;
  since 2026-07-22 that check matches on the parsed **host** rather than on a
  substring of the URL, and the YouTube list is `youtube-nocookie.com`,
  `ytimg.com` and `googlevideo.com` — `www.youtube.com` is refused, so the
  player's own "Watch on YouTube" link cannot navigate the frame onto the
  tracking origin.

Known residual hardening: the render-path symlink cache is keyed by path for the
session, so a symlink swapped *after* its first render isn't re-checked (a
narrow TOCTOU on an already-open deck).

## Crash-recovery snapshots

Autosave writes each dirty tab's full markdown (and user notes) as **unencrypted
JSON** to `<app-support>/recovery/<uuid>.json`, so work survives a crash. This
means deck content — including a **classified** deck — sits in plaintext on disk
until the tab is saved or discarded. Mitigations: the directory is the per-user,
OS-permissioned app-support path; snapshots are deleted on save, on "tab became
clean" and on a normal window close; and orphans older than 7 days are pruned
both at startup (`RecoveryService.pruneOlderThan` via `loadAll`) and while the
app runs (`pruneIfDue`, rate-limited to once an hour, driven by the autosave
tick) so a long-uptime machine cannot hold a forgotten crash file indefinitely.

**Encryption at rest was considered and deliberately not implemented.** The only
defensible key location is the OS keychain — a key stored beside the ciphertext
is not encryption — and the app already uses that store. But a snapshot almost
always duplicates a deck that exists as an unencrypted `.md` in the user's own
project folder, on the same disk under the same permissions; encrypting the copy
while the original lies beside it protects only the never-saved deck, which is
also the shortest-lived case. Against that: OciDeck ships no symmetric cipher
(`crypto` provides hashes only), so this means adding a full cryptography
library to the dependency tree and SBOM of the whole application, or hand-rolling
a cipher inside a privacy tool. It also costs recoverability — a snapshot that is
unreadable without its keychain entry fails silently on a restored machine, at
precisely the moment recovery exists for. Bounding the plaintext's lifetime and
making the OS-permission claim actually true was judged the better trade.

That second half is a real fix, not a restatement. On macOS `~/Library` is 0700
and `$TMPDIR` is per-user, so the "per-user, OS-permissioned" claim holds by
itself. On **Linux** it did not: `getApplicationSupportDirectory()` and the
media-staging root under `/tmp` are created with the ordinary umask, leaving deck
content and the images of an unsaved deck readable by any other local account.
`DiskTraces.restrictToOwner()` now runs one fixed `chmod 700` over both at
startup (Linux only, argv form, no shell, best effort, never `/tmp` itself).

A connected **git repository** puts far more than a snapshot there: a native
clone under `<app-support>/git_clone/<storageSlug>/` holds the full deck content
*and its history*, next to a draft store and an outbox of commits not yet
pushed, all unencrypted. The 7-day prune deliberately does not apply — a working
copy is meant to persist. Whatever sensitivity the repository has on the server,
it has on this disk too.

Removing the connection now removes all of it. `SettingsNotifier.setConnections`
is the single funnel for every connection-list mutation, and it hands each
disappeared connection to `DiskTraces.removeTracesOf`, which deletes
`git_clone/<slug>/`, `git_mirror/<slug>/` and the `git_outbox::<slug>::` keys.
The keychain secret survives on purpose (it belongs to the account, not to this
connection), and a `LocalConnection` is never touched — that path is the user's
own folder.

The one case where cleanup is refused is **unpushed work**. Queued commits exist
nowhere else, so `removeGitTraces` returns a refusal and leaves the working copy
alone unless the caller passes `discardPendingWork`. The settings dialog obtains
that flag only from an explicit confirmation that names the deck, branch and
commit message at stake; declining keeps the connection. The same rule guards
`SettingsNotifier.resetToInitialState`, which otherwise wipes settings, recovery
snapshots, style logos, every working copy and the per-connection keychain
entries. *Corrected 2026-07-22: this section previously documented that none of
this was cleaned up. That was accurate then; the behaviour, not the wording, was
the defect.*

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

Releases are tagged (latest `0.1.1`, 2026-07-27). The app displays its version
under **Settings → Over OciDeck**, but the version number only changes when
someone bumps `pubspec.yaml`, which does not happen on every commit, so many
different commits on the default branch can show the same number. Quoting it
narrows down roughly what you ran; it does not tell you whether a fix has landed
since — for that, the commit is still what matters. Fixes land on the default
development branch. The latest release and the default branch are both
supported; fixes target the latest release plus that branch.

*(Corrected 2026-07-28: this said "There is no released version yet" and
"There are no releases" — true until `0.1.0` on 2026-07-25, stale since.)*

## Finding this the standard way

*Added 2026-07-22.* The web build serves its own
[`/.well-known/security.txt`](web/.well-known/security.txt) (RFC 9116), so a
researcher who follows the standard discovery route lands on the same mailbox
this file names. Delivery to that address was tested by the publisher on
2026-07-22.

The publisher's own site carries a separate `security.txt` covering the
foundation rather than this application; the two are expected to name the same
mailbox.

## The same facts, machine-readable

*Added 2026-07-22.* [`security-insights.yml`](security-insights.yml) carries the
contact, the policy links, the licence and the tooling in the OpenSSF Security
Insights format (v2.2.0), so a downstream user's tooling can read them instead of
someone reading this file and re-typing them. A test fails if the two disagree
about the reporting address or the licence.

## End of life and what "supported" means

*Added 2026-07-22.* Nothing in this repository said anything about the other end
of a project's life, and that is the first thing an outsider checks. A quiet
month should not have to be read as a signal.

**What is supported, today.** The latest tagged release and the default
development branch. A fix lands on the default branch and is backported to the
latest release where applicable — see [Supported versions](#supported-versions).

*(Corrected 2026-07-28: this said "The default development branch, and nothing
else" and "There are no releases" — stale since `0.1.0` on 2026-07-25.)*

**What discontinuation would look like.** If this project stops, it will be said
plainly rather than left to be inferred:

- a notice at the top of [`README.md`](README.md) and of this file;
- an entry in [`CHANGELOG.md`](CHANGELOG.md);
- the issue tracker set to read-only rather than left open to collect reports
  nobody will read.

**Notice.** At least **three months** between that notice and the point where
vulnerability reports stop being answered. That is chosen to be a period one
maintainer can actually honour — a longer promise made by a project with a bus
factor of one (see [`CONTRIBUTING.md`](CONTRIBUTING.md)) would be a promise about
someone's future circumstances, and this file does not make those.

**What happens to reports after that.** They stop being answered, and the
[Reporting a vulnerability](#reporting-a-vulnerability) section will say so. An
unmaintained project that still accepts vulnerability reports is worse than one
that says it does not: it absorbs a finder's effort and returns nothing, and it
leaves users believing someone is watching.

**Archiving, not deletion.** The source stays available under its licence, and
anyone may fork it and continue. That is the real continuity guarantee here, and
it is stronger than any support window this project could credibly offer — it
does not depend on us still being here. It is the same reasoning that keeps every
deck in plain Markdown: your work should be able to outlive the tool.

## How a fix reaches you

Stated plainly, because the honest answer is thinner than most projects' and a
reader deserves to know it before relying on this (*added 2026-07-22*).

There is **no update mechanism**. The app never phones home and never checks for
a newer version — showing you its own version (see [Supported
versions](#supported-versions)) is not the same as knowing whether a newer one
exists. There is no release feed to subscribe to, no signed installer that
updates itself, and no notification of any kind. A fix reaches you when you
fetch the default branch and rebuild — and not before.

So the notification channel is the repository itself. Three places carry it, in
increasing detail:

- **[`CHANGELOG.md`](CHANGELOG.md)** — the `[Unreleased]` section, written in the
  user's language rather than in commit shorthand. This is the one to read if you
  only read one.
- **The commit log and the merged pull requests** on the default branch. Every
  change lands through a PR, so the PR is where the reasoning is.
- **This file**, for anything about a bundled component that is deferred rather
  than fixed — see [Vendored bundle
  currency](#vendored-bundle-currency).

### Subscribing, rather than remembering to look

*Added 2026-07-22.* All three of the above are pull: you have to think of it. For
a fixed vulnerability that is the wrong way round, so here is what can be
followed, stated with its limits (verified against the forge on 2026-07-22).

| Feed | URL | What it carries today |
|---|---|---|
| **Releases** | `https://pawprint.vigilis.online/LibreKAT/Ocideck/releases.rss` | Tagged releases (`0.1.0`, `0.1.1`, …) with notes, SBOM and `SHA256SUMS` |
| **Tags** | `https://pawprint.vigilis.online/LibreKAT/Ocideck/tags.rss` | Release tags (`v0.1.0`, `v0.1.1`, …) plus `archive/git-mirror`, which is an archived branch and not a version |
| **Repository activity** | `https://pawprint.vigilis.online/LibreKAT/Ocideck.rss` | Everything — pushes, comments, branch deletions. Real, and mostly noise |

**The releases feed is the one to subscribe to**: the day it carries a new
item, that item is a release, and a security fix will be in
its notes. Subscribing to a feed costs nothing and is the only way to be
told rather than to have to ask. The activity feed is what exists for
everything between releases, and it will not distinguish a security fix from a
branch deletion — which is why it is listed here as available rather than
recommended.

*(Corrected 2026-07-28: this said the releases feed was empty "because there
are no releases yet" — stale since `0.1.0` on 2026-07-25.)*

There is deliberately **no mailing list**. A subscriber list is personal data we
would then hold, protect and eventually have to delete; a feed is a file on a
server that nobody has to register for. Given what this project promises about
data, that asymmetry decides it.

**A security fix is marked in the changelog.** From 2026-07-22, an entry in
[`CHANGELOG.md`](CHANGELOG.md) that closes a vulnerability opens with
**`Security:`** so it is recognisable as one at a glance, in the file and in any
feed item that quotes it. A feed only helps if the item in it can be told apart
from the rest.

If you reported something, you also get told directly: the correspondent named
under [What happens to your report](#what-happens-to-your-report-on-our-side)
points you at the commit that closes it.

What this means for a deployment that matters: pin the commit you built from and
record it, because the version number alone does not pin down the commit, and
decide yourself how often you refetch. The project cannot tell you that you are
behind. When a release introduces a breaking change, this section and
[`docs/MIGRATION_GUIDE.md`](docs/MIGRATION_GUIDE.md) are where it gets written
down.

*(Corrected 2026-07-28: this said "the commit is the only version identifier
that exists" — releases are tagged now, but the point about pinning the commit
still stands because the version number is not bumped on every commit.)*

### Release artifact integrity and signing

*Added 2026-07-31.* Every release carries `SHA256SUMS` over all of its files. A
checksum proves you have the bytes that were published here; on its own it is
**not** a signature and says nothing about *who* published them. The stronger
guarantee is deliberately asymmetric per platform:

- **macOS** is signed with a Developer ID and notarised by Apple
  (`scripts/notarize_macos.sh`), which attests the publisher.
- **Windows and Linux** ship with `SHA256SUMS` and **no code signature**. For
  Windows this is a weighed decision, not a gap (#1013, closed 2026-07-31): since
  March 2024 no Authenticode certificate type — OV or EV — buys instant
  SmartScreen trust, reputation is earned only by download volume, and every paid
  route would put either a hardware token or a signing secret into the release
  path, against the least-privilege line this project holds. Building from source
  is the provenance route that needs no signature and no trust in our build
  machine: the toolchain is pinned and every artifact comes from a workflow you
  can read. Linux signing (#1014) remains an open question.

If the SmartScreen warning ever becomes a real barrier, the fallback is an OV
certificate signed by hand on a local machine — the same manual model as the
macOS notarisation — never a secret in CI. The full account is in
[`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md#releases-are-alpha-and-unsigned)
and [`docs/BUILD.md`](docs/BUILD.md#signing-status-of-the-published-artifacts).
