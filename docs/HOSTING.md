# OciDeck — Hosting & Deployment Guide

> **Status:** procedure, current — for whoever serves the web build · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

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
- copies `LICENSE.md`, `THIRD_PARTY_NOTICES.md` and the SBOM (both
  machine-readable formats + the Markdown view) into the bundle, so the licence
  terms and the EU-CRA artefact travel with the distribution;
- writes `build/web/SHA256SUMS` over the finished bundle, and prints the sha256
  of that file — the one value to publish alongside a download; and
- normalises file permissions to world-readable (`644`/`755`) so a locally
  `600` asset doesn't become a silent `403` on the server.

**Serve all of them.** They are the artefacts a downstream user or auditor needs
to establish what you handed them; a deployment that 404s on `/LICENSE.md` or
`/sbom/` still works but can no longer account for itself.

You can sanity-check the hardening with `make check-web`
(`tool/check_web_hardening.dart` plus `tool/pack_web_release.dart --check`, which
verifies that nothing was added, changed or lost after packing).

## 2. Serve `build/web/` statically

Any static host works — a bucket (S3/GCS), a CDN, Nginx/Apache/Caddy, Nextcloud's
web root, or, for a quick local check:

```bash
cd build/web && python3 -m http.server 8080
```

That one-liner is for a **local check only**. It serves nothing compressed, and
this bundle is large enough that the difference is the whole first impression.

Serve over **HTTPS** in production.

### Publishing an update: `make deploy-web`

Copying a new bundle over a live directory means visitors briefly get a mixture
of old and new files, and `main.dart.js` from one build with assets from another
is a white screen. `scripts/deploy_web.sh` (via `make deploy-web`) avoids that:

1. verifies the bundle — `SHA256SUMS` must describe exactly the files present,
   so a half-finished build cannot leave;
2. uploads a tarball and unpacks it **beside** the live directory;
3. swaps the two directories with `mv`, which is atomic to the web server;
4. fetches `/index.html` and `/SHA256SUMS` back over HTTPS and compares them
   byte for byte with what was just deployed — a cache or CDN in between is
   exactly the failure this catches;
5. only then removes the backup it left behind, so a rollback stays one `mv`.

```bash
make build-web && make deploy-web
```

It targets the public web demo by default. Override with the environment:
`OCIDECK_DEPLOY_HOST`, `OCIDECK_DEPLOY_ROOT`, `OCIDECK_DEPLOY_OWNER`,
`OCIDECK_DEPLOY_URL`. `--dry-run` shows what it would do; `--keep-backup` keeps
the previous version around.

If step 4 fails, the script exits non-zero **and leaves the backup in place**.
That is deliberate: an unverified deployment is the one you most want to be able
to undo.

### Automatic deployment on a tag

`.forgejo/workflows/release.yml` runs the very same script, so a hand deployment
and a tag deployment are the same sequence — see
[BUILD.md](BUILD.md#cutting-a-release). It needs two repository secrets on the
forge (Settings → Actions → Secrets):

- **`DEPLOY_SSH_KEY`** — the private half of a key that may reach the host.
  Generate a dedicated one; do not reuse a personal key:

  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/ocideck-deploy -C "ocideck-deploy" -N ""
  ssh-copy-id -i ~/.ssh/ocideck-deploy.pub ubuntu@braniebananie.nl
  ```

  Paste the contents of `~/.ssh/ocideck-deploy` (the file **without** `.pub`)
  into the secret.

- **`DEPLOY_KNOWN_HOSTS`** — the host's public key, pinned ahead of time:

  ```bash
  ssh-keyscan -t ed25519 braniebananie.nl
  ```

  Run this from a machine you trust, look at it once, and paste the line.
  The workflow will not run `ssh-keyscan` itself: trusting whatever key answers
  at deploy time is precisely the assumption a man-in-the-middle needs.

The account behind that key needs write access to the web root — on the
reference deployment it is `ubuntu`, and the web root is owned by `brenno`, so
the script uses `sudo` for the unpack and swap.

Missing either secret makes the `deploy-web` job **skip** the live step — it does
not fail, so a tag produces no red job or failure mail. The release itself still
publishes: the desktop downloads do not depend on the web host. Put the web
version live by hand with `make deploy-web` until both secrets are set.

### Enable compression — this is not optional in practice

Turn on brotli or gzip for `.js`, `.wasm`, `.json` and `.ttf`. Measured on this
tree with `make build-web` on 2026-07-22, what a browser fetches **before the
first paint**:

| Part | Raw | Compressed |
| --- | --- | --- |
| `main.dart.js` | 13.8 MB | 3.8 MB |
| `canvaskit/canvaskit.wasm` | 6.9 MB | 2.8 MB |
| Fonts in `FontManifest.json` (18 files: 4 variable TTFs, Material icons, KaTeX) | 2.7 MB | 1.4 MB |
| `assets/privacy/health_lexicon.json` — awaited before `runApp` | 2.0 MB | 0.5 MB |
| **Total before the first frame** | **~25 MB** | **~9 MB** |

Uncompressed that is roughly 25 MB and tens of seconds of blank white on an
ordinary connection. There is no loading indicator in `web/index.html` yet, so
the visitor has nothing to look at while it arrives.

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
For a publicly reachable deployment these stop being recommendations — see
§4b.2 and the release conditions in the checklist.

**Apache hosts: it already ships.** The bundle carries a `web/.htaccess` (copied
to `build/web/.htaccess` by `flutter build web`) that sets the full CSP header,
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy:
no-referrer`, a `Permissions-Policy`, and HSTS. It takes effect automatically —
**if** `mod_headers` is enabled and `AllowOverride` for the web root permits
`FileInfo` (or `All`). Where `AllowOverride` is `Off`, Apache ignores the file
silently; move the same directives into the vhost/server config. Non-Apache hosts
ignore `.htaccess` entirely and still need the snippets above. The header CSP is
kept byte-for-byte identical to the `<meta>` one by a test and the web-hardening
check.

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
  metadata targets, pins the resolved address, blocks redirects, caps bytes, and
  only allows ports 80/443/8080/8443), so it can't be turned into an
  internal-network scanner or a port scanner.
- It is stateless: it forwards bytes and stores nothing, and it keeps the target
  URL out of its log lines.
- Setup and configuration: see
  [`server/fetch-proxy/README.md`](../server/fetch-proxy/README.md).

Deploy it on the same origin as the app (e.g. reverse-proxy `/fetch-proxy` to it)
so the app's `connect-src 'self'` covers it.

### 4a. What the proxy does *not* protect against

Out of the box the proxy serves only requests carrying
`Sec-Fetch-Site: same-origin`. That is a real barrier against *pages*: the header
is on the forbidden-header list, so no cross-site page can set it, and no site
other than yours can make a browser send it. It is **not** a barrier against
anything that isn't a browser. A `curl -H "Sec-Fetch-Site: same-origin"` passes
it without effort, and there is no header that proves a request came from a real
browser — so this cannot be fixed inside the proxy. The module documents this
itself, in the comment above `_origin_allowed` in
[`server/fetch-proxy/ocideck_fetch_proxy.py`](../server/fetch-proxy/ocideck_fetch_proxy.py).

The consequence is narrow but real: an unconfigured, publicly reachable proxy is
an open fetch relay for third parties. What bounds the damage is the SSRF rule
set above, and that set always applies — internal targets stay unreachable
whatever the caller does. What is *not* bounded is that strangers can pull
public URLs through your server, in your name and from your IP address.

That is a deployment property, not a defect, which is why the conditions below
are stated as requirements rather than as advice.

### 4b. Requirements before you expose a deployment publicly

These three are conditions, not recommendations. If you cannot meet them, do not
deploy the proxy — the web build works without it (§5).

1. **Never reachable from the internet without either an origin allowlist or
   authentication.** The proxy binds to `127.0.0.1:8123` by default
   (`OCIDECK_PROXY_BIND`/`OCIDECK_PROXY_PORT`); leave it there and let the
   reverse proxy be the only way in. If the proxy sits strictly same-origin
   behind the app and is not otherwise routable, that is enough on its own.
   Anything beyond that needs `OCIDECK_PROXY_ALLOWED_ORIGINS` set to your app's
   origin **and** authentication in front of `/fetch-proxy` on the reverse proxy.
   The proxy itself has no authentication and no rate limiting of its own — it
   caps concurrency, not callers.
2. **The HTTP security headers are set on the static host.** `X-Frame-Options:
   DENY`, the CSP as a real response header rather than only the `<meta>` tag
   (§3), `X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer`.
   §3 lists the last two as companions for the ordinary case; for a public
   deployment treat all four as required. The header snippets per web server are
   in [BUILD.md](BUILD.md).
3. **`OCIDECK_PROXY_ALLOW_ANY=1` only behind authentication and rate limiting.**
   That variable turns the origin check off entirely and makes the endpoint an
   open — SSRF-bounded, public-hosts-only — fetcher for anyone who finds it. If
   you run it that way, also lower the two ceilings from their defaults:
   `OCIDECK_PROXY_MAX_BYTES` (default 536870912, i.e. 512 MiB per request) and
   `OCIDECK_PROXY_MAX_INFLIGHT` (default 8 concurrent requests; further requests
   get a 503). Without authentication, rate limiting and lowered ceilings, an
   open proxy is an anonymisation relay running in the operator's name — the
   process says as much in a warning on startup.

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

## 6. Compliance artefacts

Five things are served from the bundle itself, and all five should stay
reachable:

| Path | What it is for |
| --- | --- |
| `/sbom/` (`ocideck.cdx.json`, `ocideck.spdx.json`, `ocideck.sbom.md`) | The CRA inventory matching the exact build you shipped. → [SBOM.md](SBOM.md) |
| `/LICENSE.md` | The terms under which you may serve it, and the recipient may pass it on. |
| `/SOURCE.md` | Where the source of this compiled bundle lives. **Hosting counts as communicating the Work under EUPL-1.2 article 1, so article 5's source indication applies to you, not only to us.** If you serve a modified bundle, point it at your source. |
| `/THIRD_PARTY_NOTICES.md` | The attribution the dependencies require. → [LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) |
| `/SHA256SUMS` | Lets someone confirm their copy of the bundle is complete and undamaged. |

If you offer OciDeck as a **download** rather than only as a hosted app, publish
the sha256 of `SHA256SUMS` next to the download link — over a different channel
than the file itself, since a checksum served from the same place proves nothing
against whoever can replace both. →
[BUILD.md](BUILD.md#verifying-a-bundle-you-downloaded)

## 7. Optional: server-side deck library

By default the web build asks each visitor to open a file from their own
machine — there is no server-side storage. If you want to host a library of
presentations on the same server and let visitors browse them, you can do so
with **only static files and your web server's built-in directory listing** —
no backend, no API, no application server.

### How it works

1. You put `.md` files in a directory on the server (e.g. `/var/www/decks/`).
2. You enable directory listing for that directory (Apache `Options +Indexes`,
   Nginx `autoindex on`).
3. You place a small config file at the app's root that tells the web app where
   to look.
4. The web app fetches the directory listing, parses the `.md` links, and shows
   them on the welcome screen under "Presentaties op deze server". When a
   visitor picks one, the app fetches that `.md` over HTTPS (same origin) and
   opens it in the browser tab — the same in-memory flow as URL import.

### Configuration file

Create `ocideck-web-config.json` at the root of the app (the same directory as
`index.html`):

```json
{"decksPath": "/decks/"}
```

- `decksPath` is the URL path to the directory with your `.md` files. It can be
  absolute (`/decks/`) or relative to the app (`decks/`).
- If the file is absent or `decksPath` is missing, the feature is off — the
  welcome screen shows no server-deck section. This is the default, so existing
  deployments are unaffected.

### Web server configuration

**Apache** — enable autoindex for the decks directory:

```apache
<Directory /var/www/decks>
  Options +Indexes
  AllowOverride None
  Require all granted
</Directory>
```

**Nginx** — enable autoindex for the decks location:

```nginx
location /decks/ {
  autoindex on;
}
```

Both produce HTML pages with `<a href="file.md">` links that the web app
parses. Subdirectories are not followed — the listing is flat.

### Security notes

- The decks directory is **public** — anyone who can reach the app can read the
  listings and the `.md` files. Put only public presentations there.
- Fetching is same-origin (`connect-src 'self'`), so the CSP does not need to
  change.
- The `.md` files pass through the same security gate as URL import: executable
  content is refused at open time.

## Checklist

Everything under "Release conditions" is a condition for a publicly reachable
deployment: not met means not deployed. The rest is the ordinary hygiene of
serving a static bundle.

**Release conditions (public deployment)**

- [ ] CSP sent as an HTTP header — not only via `<meta>` — with `frame-ancestors`
      set for your embedding needs (§3)
- [ ] `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff` and
      `Referrer-Policy: no-referrer` set on the app's HTML (§3, [BUILD.md](BUILD.md))
- [ ] `Strict-Transport-Security` sent on every response (§3)
- [ ] If the fetch-proxy is deployed: it is bound to `127.0.0.1` and reachable
      only through the reverse proxy (§4b.1)
- [ ] If the fetch-proxy is reachable beyond a strictly same-origin path:
      `OCIDECK_PROXY_ALLOWED_ORIGINS` set **and** authentication in front of
      `/fetch-proxy` — its own origin check is a header heuristic that any
      non-browser client can send (§4a, §4b.1)
- [ ] If `OCIDECK_PROXY_ALLOW_ANY=1`: authentication and rate limiting in front
      of it, and `OCIDECK_PROXY_MAX_BYTES`/`OCIDECK_PROXY_MAX_INFLIGHT` lowered
      from their defaults (§4b.3)

**Ordinary deployment steps**

- [ ] `make build-web` succeeds and `make check-web` passes
- [ ] Served over HTTPS from a static host
- [ ] fetch-proxy deployed on the same origin **only if** web URL import is needed
- [ ] `/sbom/` reachable
- [ ] Users told what the web build cannot do (§5) — the missing image privacy
      check in particular, if they present photographs of people
- [ ] If hosting a server-side deck library (§7): `ocideck-web-config.json`
      placed, autoindex enabled, and only public presentations in the decks
      directory
