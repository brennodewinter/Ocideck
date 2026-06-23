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
- **SSRF — hostname resolution.** URL import resolves the host and rejects it
  if *any* resolved address is internal (loopback / private / link-local /
  metadata), closing the bypass where a public hostname points at an internal
  IP. (A narrow DNS-rebinding window remains because the socket is not pinned.)
- **Symlink containment.** The copy-to-clipboard sink resolves the real
  (symlink-followed) path and refuses it if it escapes the project
  (`resolveContainedRealPath`), so a project-internal symlink to an outside file
  can't be exfiltrated. Package import already skips symlink entries. The
  per-frame render path keeps the fast lexical guard (a filesystem stat per
  image per frame would jank on network-mounted projects); a *displayed*
  symlinked image is decoded to pixels but its bytes are never handed out.
- **Per-asset import validation.** Picked/pasted images are validated by magic
  bytes (PNG/JPEG/GIF/BMP/WebP), not just the file extension, and capped at
  64 MiB; video/audio imports are capped at 1 GiB.

Known residual hardening tracked for future work: pinning the URL-import socket
to the validated IP (full DNS-rebinding protection), and realpath symlink
containment on the export render path (currently lexical for performance).

## Supported versions

Security fixes target the latest released version and the default development
branch. Older versions may not receive fixes.
