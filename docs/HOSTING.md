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
`X-Frame-Options` to match `frame-ancestors`.

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

- No native filesystem access — open/save go through the browser; large decks
  live in tab memory.
- More memory-constrained than desktop; very large media can destabilise a tab.
- Cloud AI is **blocked on web** by design (see [SECURITY_DESIGN.md](SECURITY_DESIGN.md) §7).

## 6. Compliance artefact

The SBOM is served at `/sbom/` (`ocideck.cdx.json`, `ocideck.spdx.json`,
`ocideck.sbom.md`). Leave it reachable so downstream users/auditors can retrieve
the CRA inventory that matches the exact build you shipped. See [SBOM.md](SBOM.md).

## Checklist

- [ ] `make build-web` succeeds and `make check-web` passes
- [ ] Served over HTTPS from a static host
- [ ] CSP sent as an HTTP header, with `frame-ancestors` set for your embedding needs
- [ ] `Referrer-Policy`, `X-Content-Type-Options` headers set
- [ ] fetch-proxy deployed on the same origin **only if** web URL import is needed
- [ ] `/sbom/` reachable
