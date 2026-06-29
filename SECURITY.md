# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, report them privately via GitHub's **"Report a vulnerability"** button
under the repository's **Security** tab (Security Advisories). If that is not
available to you, contact the maintainer directly and wait for a reply before
disclosing anything publicly.

When reporting, please include as much of the following as you can:

- A description of the issue and its impact.
- Steps to reproduce (a minimal deck or input file if relevant).
- The OciDeck version, operating system, and Flutter version.
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

OciDeck is an offline desktop application. Areas of particular interest:

- Parsing of untrusted decks (`.md`), packages (`.ocideck`), sidecars
  (`.ink.json`, captions), and linked CSV data.
- Importing presentations from a URL.
- The HTML export, which inlines third-party JavaScript (marked, highlight.js,
  mermaid, MathJax) to render offline.
- The export classification gate (`ClassificationPolicy`) — any way to export a
  deck classified above the configured release ceiling.
- The **web build's self-contained guarantee.** Built with `make build-web`, the
  browser app bundles CanvasKit and the UI font locally (no gstatic CDN) and runs
  under a strict Content-Security-Policy in `web/index.html` (`script-src 'self'
  'wasm-unsafe-eval'`, no `unsafe-inline`/`unsafe-eval`; media first-party). Any
  way to make the running app load third-party script or origins is in scope.

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
  guards; URL imports use an `http`/`https` allowlist with an SSRF host
  blocklist and no redirect following.
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
  and is scoped to user-enabled sessions. Remote images keep the decode-dimension
  cap (`cappedNetworkImage`); magic-byte validation does not apply to live
  streams (no pre-fetched bytes), a deliberate trade-off. The embed WebView
  restricts navigation to the player origins and refuses auth prompts/pop-ups.

Known residual hardening: the render-path symlink cache is keyed by path for the
session, so a symlink swapped *after* its first render isn't re-checked (a
narrow TOCTOU on an already-open deck).

## Supported versions

Security fixes target the latest released version and the default development
branch. Older versions may not receive fixes.
