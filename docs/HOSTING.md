# OciDeck — Hosting & Deployment Guide

How to build and serve the OciDeck **web** build safely. The desktop apps are
built as native binaries and need no hosting; this guide is about the web
bundle. For build internals see [BUILD.md](BUILD.md); for the security rationale
see [SECURITY_DESIGN.md](SECURITY_DESIGN.md).

## Key idea: there is no backend

OciDeck's web build is a **static, self-contained** bundle. There is no
application server, database, or API to run — you serve a directory of files from
any static host. The app processes everything in the browser tab; user content
never touches your server (the one exception is the optional fetch-proxy, below,
which only forwards bytes and stores nothing).

## 1. Build the bundle

```bash
make build-web
```

This runs `flutter build web --release --no-web-resources-cdn --csp` plus the
security prerequisites, and produces `build/web/`. What the flags buy you:

- `--no-web-resources-cdn` — CanvasKit is served from **your** origin, not the
  gstatic CDN, so the running app pulls **zero third-party origins**.
- `--csp` — a CSP-safe loader (no inline/`eval` scripts).

The build also:
- copies the SBOM to `build/web/sbom/` (both machine-readable formats + the
  Markdown view), so the EU-CRA artefact travels with the distribution; and
- normalises file permissions to world-readable (`644`/`755`) so a locally
  `600` asset doesn't become a silent `403` on the server.

You can sanity-check the hardening with `make check-web`
(`tool/check_web_hardening.dart`).

## 2. Serve `build/web/` statically

Any static host works — a bucket (S3/GCS), a CDN, Nginx/Apache/Caddy, Nextcloud's
web root, or, for a quick local check:

```bash
cd build/web && python3 -m http.server 8080
```

Serve over **HTTPS** in production.

## 3. Set the Content-Security-Policy as an HTTP header

The bundle ships a strict CSP in a `<meta>` tag, which covers most directives.
But a `<meta>`-delivered CSP **cannot enforce `frame-ancestors`** (browsers
ignore it outside an HTTP header). To control who may embed the app, send the CSP
as a real response header. A good baseline mirrors the meta policy and adds an
enforceable `frame-ancestors`:

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https:; worker-src 'self' blob:; child-src 'self' blob: data:; frame-src 'self' blob: data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'
```

Copy it exactly, `child-src` and `frame-src` included. A header CSP and a meta
CSP are enforced **cumulatively** — per directive the stricter one wins — so
leaving those two out does not fall back to the meta policy that has them. It
falls back to `default-src 'self'`, and the `blob:`/`data:` frames the app
relies on stop loading.

- **Standalone hosting:** keep `frame-ancestors 'none'` (no embedding).
- **Embedding inside Nextcloud (or another host):** set
  `frame-ancestors https://your-nextcloud.example` instead of `'none'`.
- `connect-src` includes `https:` so the user-initiated **URL import** can reach
  arbitrary HTTPS sources. If you don't want that in your deployment, tighten
  `connect-src` to `'self'`.

Recommended companion headers: `Referrer-Policy: no-referrer`,
`X-Content-Type-Options: nosniff`, and (for embedding control on old browsers)
`X-Frame-Options` to match `frame-ancestors`. The bundle itself already carries
`<meta name="referrer" content="no-referrer">` — unlike `frame-ancestors`, that
one *is* honoured from a meta tag — so the header only reinforces what ships.

### `Strict-Transport-Security`

Send it, and send it on every response:

```
Strict-Transport-Security: max-age=63072000; includeSubDomains
```

Without HSTS the first request to a host a user types without a scheme goes out
over plaintext, and a redirect to HTTPS is exactly the moment an attacker on the
path gets to answer instead. That matters more here than for a typical static
site: the URL-import and the fetch-proxy make this origin one that decks link
*to*, so a downgrade reaches more than the one visitor in front of you.

Only add `preload` if you accept what it means — the domain and every subdomain
become HTTPS-only in shipped browsers, and getting removed from the list again
takes months. `includeSubDomains` alone is the safe default.

*(Added 2026-07-22: HSTS was recommended nowhere in this repository before.)*

## 4. Optional: the fetch-proxy (for web URL import)

Importing a deck or asset from a URL works directly on desktop, but in a browser
it is subject to CORS. For sources that don't send permissive CORS headers, the
web build falls back to a small **fetch-proxy** endpoint (`fetch-proxy?url=…`)
that fetches server-side and returns the bytes.

- It is **optional** — without it, only CORS-friendly sources import on web.
- It enforces the **same SSRF rules as NetGuard** (rejects internal/private/
  metadata targets, pins the resolved address, blocks redirects, caps bytes), so
  it can't be turned into an internal-network scanner.
- It is stateless: it forwards bytes and stores nothing.
- Setup and configuration: see
  [`server/fetch-proxy/README.md`](../server/fetch-proxy/README.md).

Deploy it on the same origin as the app (e.g. reverse-proxy `/fetch-proxy` to it)
so the app's `connect-src 'self'` covers it.

## 5. Web build limitations to communicate

The web build is not the desktop app in a browser. A browser has no filesystem,
no subprocesses and no FFI, so a set of features is absent there — not disabled
by a setting the user can find, but simply not present. Tell your users before
they go looking.

The single source of truth for the first block is
`lib/platform/platform_features.dart`; the rest are `kIsWeb` branches in the
services named below.

| Feature | Web | Why |
|---|---|---|
| Local project folders, sidecar files | ✗ | No filesystem. Open/save go through the browser; decks live in tab memory. |
| WebDAV / Nextcloud as a deck source | ✗ | The client is `dart:io` with its own SSRF pinning, and from a browser it would need CORS agreed with the server admin. |
| S3 buckets as a deck source | ✗ | The client is `dart:io` with hand-rolled SigV4 and its own SSRF pinning; a browser has neither, and would need CORS agreed on the bucket. |
| Git as a deck source | ✓ | Over the REST transport (`git_transport_web.dart`), under the same security gate as URL import (§4). The native `git` subprocess is unavailable on web, so there is no local clone or offline merge — commits go straight to the forge — but open and save both work. |
| Second-screen presenter view | ✗ | Needs native windowing. |
| Crash recovery / autosave snapshots | ✗ | No app-support directory, so every snapshot call is a no-op and the autosave timer is not even started. **Nothing is recovered after a browser crash.** It is no longer silent, though: the app says so once at the user's first edit, and a `beforeunload` guard makes the browser ask before a tab with unsaved work closes. That guard is the only lever a browser offers here, and its wording belongs to the browser. |
| Face detection in slide images | ✗ | The detector is a native library over FFI. See below — this one has a privacy consequence. |
| Local CVE database (offline lookup) | ✗ | Needs a multi-gigabyte on-disk index. The online CVE lookup is also desktop-only — it runs through an SSRF-pinned `dart:io` request the browser can't make; the in-app button says so. |
| Image caption sidecars | ✗ | Sidecars are files next to the image; there are none. |
| "Missing media" slide-quality check | ✗ | It resolves paths on disk. |
| Cloud AI | ✗ | Blocked by design, not by platform — see [SECURITY_DESIGN.md](SECURITY_DESIGN.md) §7. |
| URL import of decks | ✓ | Works on web through the fetch-proxy, under the same security gate as desktop (§4). |
| Export (PDF, PPTX, HTML), sealing, encrypted packages | ✓ | Delivered as browser downloads. |

Also: the web build is more memory-constrained than desktop, and very large
media can destabilise a tab.

### The one to say out loud: face detection

The privacy check has two halves — it scans text, and it looks at images for
recognisable faces. On web **only the text half runs**.

This matters more than a missing feature normally would, because the failure is
silent in the worst possible direction: a deck that a desktop user would be
warned about ("at least 2 recognisable faces on slide 4") produces no image
warning at all in a browser. The app itself is honest about this — the panel
listing which checks ran leaves the image check out rather than reporting zero
findings, precisely so "we found nothing" is never confused with "nobody
looked". Make sure the people using your deployment know which of the two they
are seeing.

If your users handle decks containing photographs of people, this is a reason
to give them the desktop build.

## 6. Compliance artefact

The SBOM is served at `/sbom/` (`ocideck.cdx.json`, `ocideck.spdx.json`,
`ocideck.sbom.md`). Leave it reachable so downstream users/auditors can retrieve
the CRA inventory that matches the exact build you shipped. See [SBOM.md](SBOM.md).

## Checklist

- [ ] `make build-web` succeeds and `make check-web` passes
- [ ] Served over HTTPS from a static host
- [ ] CSP sent as an HTTP header, with `frame-ancestors` set for your embedding needs
- [ ] `Referrer-Policy`, `X-Content-Type-Options` headers set
- [ ] `Strict-Transport-Security` sent on every response (§3)
- [ ] fetch-proxy deployed on the same origin **only if** web URL import is needed
- [ ] fetch-proxy put behind authentication at the reverse proxy — its own origin
      check is a header heuristic that any non-browser client can send, so an
      unauthenticated deployment is an open fetch relay to public hosts
- [ ] `/sbom/` reachable
- [ ] Users told what the web build cannot do (§5) — the missing image privacy
      check in particular, if they present photographs of people
