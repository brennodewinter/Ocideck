# OciDeck — Hosting & Deployment Guide

> **Status:** procedure, current — for whoever serves the web build · **Status last reviewed:** 2026-11-08 · **Published by:** Stichting LibreKAT

How to build and serve the OciDeck **web** build safely. The desktop apps are
built as native binaries and need no hosting; this guide is about the web
bundle. For build internals see [BUILD.md](BUILD.md); for the security rationale
see [SECURITY_DESIGN.md](SECURITY_DESIGN.md).

## Key idea: there is no backend

OciDeck's web build is a **static, self-contained** bundle. There is no
application server, database, or API to run — you serve a directory of files from
any static host. The core editor processes content in the browser tab without an editing backend.
The optional fetch-proxy below forwards bytes without storing them. Explicit
integrations, external media and release/reference lookups have their own
network paths; see [PRIVACY.md](PRIVACY.md). Browser copies are stored on the
client, accessible to scripts served by your origin, not uploaded to a storage
backend. *(Clarified 2026-11-08.)*

## 1. Build the bundle

```bash
make build-web
```

This runs the WASM + JavaScript fallback build with content hashes, modern JS
interop checks, `--no-web-resources-cdn --csp`, plus the
security prerequisites, and produces `build/web/`. What the flags buy you:

- `--no-web-resources-cdn` — CanvasKit is served from **your** origin, not the
  gstatic CDN. This flag controls engine resources, not all dynamic font fallback.
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

The bundle **cannot run from `file://`** (opening `index.html` straight from
disk). Browsers refuse the wasm/module fetches and the service worker without
an http(s) origin; the page detects this since #2661 and explains it instead of
failing with a console full of CORS errors. Always serve the directory, even
locally.

The bundle is **location-independent**: `<base href="./">` makes every asset
resolve relative to the directory it was served from, so you may install it in
a subdirectory (e.g. `https://example.org/ocideck/`) or behind a symlinked
versioned directory — no rebuild or `--base-href` needed. One edge to know:
the address must end in a trailing slash (`/ocideck/`, not `/ocideck`); every
stock web server already redirects a directory URL to its slash form, so in
practice this takes care of itself. The optional server-side deck library and
fetch-proxy (§4, §7) resolve against the same directory automatically.

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
  ssh-copy-id -i ~/.ssh/ocideck-deploy.pub ubuntu@vps-40edd80f.vps.ovh.net
  ```

  Paste the contents of `~/.ssh/ocideck-deploy` (the file **without** `.pub`)
  into the secret.

- **`DEPLOY_KNOWN_HOSTS`** — the host's public key, pinned ahead of time:

  ```bash
  ssh-keyscan -t ed25519 vps-40edd80f.vps.ovh.net
  ```

  Run this from a machine you trust, look at it once, and paste the line.
  The workflow will not run `ssh-keyscan` itself: trusting whatever key answers
  at deploy time is precisely the assumption a man-in-the-middle needs.

The account behind that key needs write access to the web root. On the
reference deployment both the SSH account and deployed files are owned by
`ubuntu`; the script still uses `sudo` for the atomic unpack and swap.

Missing either secret makes the `deploy-web` job **skip** the live step — it does
not fail, so a tag produces no red job or failure mail. The release itself still
publishes: the desktop downloads do not depend on the web host. Put the web
version live by hand with `make deploy-web` until both secrets are set.

### Enable compression — this is not optional in practice

Turn on Brotli or gzip for `.mjs`, `.js`, `.wasm`, `.json` and `.ttf`. The
shipped `.htaccess` enables gzip if `mod_deflate` is available; other hosts must
configure compression explicitly. Serve `.wasm` as `application/wasm` and
`.mjs` as `text/javascript` to enable streaming compilation and ES modules.

Historical JavaScript-only baseline: Measured on this
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
ordinary connection. The static splash in `web/index.html` remains visible while loading. Current
WASM/JavaScript measurements are in [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md).

### Cache rules for Flutter 3.50 WASM builds

Return `Cache-Control: no-cache` for `index.html`, `flutter_bootstrap.js`,
`boot.js`, `precache_manifest.json`, `version.json`, and all unhashed engine
resources under `canvaskit/` (including skwasm). Return
`Cache-Control: public, max-age=31536000, immutable` only for content-addressed
entrypoints (`main.dart.<hash>.js/.mjs/.wasm`) and assets. Engine filenames are
not hashed by `--web-content-hash`; making them immutable can mix engine and
app versions after an SDK upgrade. The supplied Apache rules implement this
policy. Do not use a blanket immutable rule for all `.wasm` files.

`deploy_web.sh` atomically swaps the completed release and retains the previous
release's hashed app/assets for already-open tabs. Only the previous release's
own manifest entries are retained, checked against its full `SHA256SUMS`;
inherited files from N-2 are not carried forward. The current release manifest
and checksum list continue to identify only the current release. A tab older
than one deployment must reload before fetching an asset unique to that older
release. For custom hosts, retain N-1 hashes too, and deploy the new loader last.
Do not rewrite missing `.wasm`, `.mjs` or asset requests to `index.html`.

The existing COOP `same-origin` and COEP `require-corp` headers also enable
skwasm rendering on a worker. Without these headers the app still starts with
single-thread rendering; local Whisper transcription still requires isolation.
No third-party engine CDN or broader CSP is needed.

## 3. Set the Content-Security-Policy as an HTTP header

The bundle ships a strict CSP in a `<meta>` tag, which covers most directives.
But a `<meta>`-delivered CSP **cannot enforce `frame-ancestors`** (browsers
ignore it outside an HTTP header). To control who may embed the app, send the CSP
as a real response header. A good baseline mirrors the meta policy and adds an
enforceable `frame-ancestors`:

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https: wss: blob:; worker-src 'self' blob:; child-src 'self' blob: data:; frame-src 'self' blob: data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'
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
  `connect-src` to `'self' blob:` (you will break meeting joins too, see below).
- `connect-src` includes `wss:` for the videocalls module: the XMPP signalling
  of a user-chosen meeting deployment travels over a secure WebSocket — the
  same bring-your-own posture as `https:`, TLS-only. Plain `ws:` is not in the
  policy; a loopback testbed on the same origin is covered by `'self'`. Drop
  `wss:` and meeting joins stop working on web.
- `connect-src` also includes `blob:`, and that one is **not** optional. A file
  dragged onto the window arrives as a blob URL and the app reads its bytes back
  over it; drop the token and drag-and-drop stops working — silently, with no
  error for the user. It opens nothing outward: a blob URL is local to the page
  that minted it and carries no byte off the machine.

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
checked against the `<meta>` policy by a test and the web-hardening check:
all shared directives match, and only the HTTP header adds `frame-ancestors`.

### Cross-origin isolation (required for local transcription)

Local transcription on web runs a pthread-based WASM build of whisper.cpp,
and WebAssembly threads need `SharedArrayBuffer`, which browsers only expose in
a **cross-origin-isolated** context. Send both headers on every response:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Without them the app still works — the engine simply reports the web capability
as unavailable, which is the honest degraded state — but local transcription
will never start. COEP `require-corp` is safe here because the CSP above already
confines every subresource axis to `'self'`, `blob:` and `data:`; the gate it
adds over `no-cors` subresource loads has nothing left to break. The
user-initiated model download is a CORS `fetch`, which COEP does not govern.

The shipped `.htaccess` sets both headers, so on Apache hosts they follow the
same rule as the rest of the header hardening: automatic when `mod_headers` +
`AllowOverride` permit it, otherwise move them into the vhost config.

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
| Local project folders, sidecar files | ✗ | No native project filesystem. Decks start in tab memory; Save also offers an explicit browser package copy. |
| WebDAV / Nextcloud as a deck source | ✗ | The client is `dart:io` with its own SSRF pinning, and from a browser it would need CORS agreed with the server admin. |
| S3 buckets as a deck source | ✗ | The client is `dart:io` with hand-rolled SigV4 and its own SSRF pinning; a browser has neither, and would need CORS agreed on the bucket. |
| Git as a deck source | ✓ | Over the REST transport (`git_transport_web.dart`), under the same security gate as URL import (§4). The native `git` subprocess is unavailable on web, so there is no local clone or offline merge — commits go straight to the forge — but open and save both work. |
| Second-screen presenter view | ✗ | Needs native windowing. |
| Crash recovery / autosave snapshots | ✗ | No app-support directory, so every snapshot call is a no-op and the autosave timer is not even started. **Unsaved changes are not recovered after a browser crash.** A deliberately saved browser copy can be reopened from Settings → Storage; it is not a recovery snapshot. It is no longer silent, though: the app says so once at the user's first edit, and a `beforeunload` guard makes the browser ask before a tab with unsaved work closes. That guard is the only lever a browser offers here, and its wording belongs to the browser. |
| Face detection in slide images | ✗ | The detector is a native library over FFI. See below — this one has a privacy consequence. |
| Local CVE database (offline lookup) | ✗ | Needs a multi-gigabyte on-disk index. The online CVE lookup is also desktop-only — it runs through an SSRF-pinned `dart:io` request the browser can't make; the in-app button says so. |
| Image caption sidecars | ✗ | Sidecars are files next to the image; there are none. |
| "Missing media" slide-quality check | ✗ | It resolves paths on disk. |
| Cloud AI | ✗ | Blocked by design, not by platform — see [SECURITY_DESIGN.md](SECURITY_DESIGN.md) §7. |
| URL import of decks | ✓ | Works on web through the fetch-proxy, under the same security gate as desktop (§4). |
| Video meetings (Jitsi) | ✓ | Proven in a real two-person call on the released bundle. Needs `wss:` in `connect-src` (§3) plus the browser's own per-site camera/microphone/display-capture permission. A browser cannot pin the server certificate — `https`/`wss` and the user's server choice are the boundary; plain `http`/`ws` is accepted only to a literal loopback address. |
| Export (PDF, PPTX, HTML), sealing, encrypted packages | ✓ | Delivered as browser downloads. |

Also: the web build is more memory-constrained than desktop, and very large
media can destabilise a tab.

### Browser copies and consent metadata

Save can keep an explicit `.ocideck` package copy in the browser profile after
confirmation. It includes embedded media, is unencrypted, and shares a 5 MiB
encoded-copy limit. Other profile users and same-origin scripts can read it;
clearing site data or browser eviction can remove it. This is not automatic
crash recovery. Settings → Storage reopens or deletes copies; resetting settings
preserves presentations but clears the separate consent journal.

The journal retains the latest 200 shown/accepted/declined warning events with
fixed identifiers, notice version and UTC time, without presentation contents or
server/account details. It is inspectable under Privacy and classification.
Deploying the app on another origin does not move copies or consent history to
that origin. Tell users to export a local backup before changing hosts or
clearing site data. See [PRIVACY.md](PRIVACY.md#extension-consent-and-browser-copies).

*(Corrected 2026-11-08: absence of native filesystem access no longer means that
all presentations are limited to tab memory.)*
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

The bundle ships an empty `ocideck-web-config.json` (`{}`), so optional
configuration reads do not produce browser-console 404 errors. Edit that file at
the root of the app (the same directory as `index.html`) to enable the library:

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
Alias /decks /var/www/decks

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
- Relative image and media references in a deck (`images/foo.png`) resolve
  against the deck file's own URL, so files placed next to the `.md` — or under
  it, like `/var/www/decks/images/` — load without extra configuration
  (`img-src`/`media-src 'self'` in the shipped CSP permits exactly that).
  References pointing outside the deck's directory or at another origin fail
  closed: the slide shows the missing-media placeholder instead.

## 8. Optional: let another website hand Markdown to OciDeck (postMessage)

A portal on **another** site — an intake form, a reporting app, a knowledge
base — can offer a Markdown text to a visitor's OciDeck without hosting it
anywhere and without putting it in a URL. OciDeck listens for `postMessage`
from the page that embeds it, asks the user for explicit permission showing
the sender's origin, and only then opens the text through the same gate as
pasted Markdown (size limit, safety scan, `marp: true` routing). The sender
only ever learns the outcome (`opened` / `declined` / `rejected` + reason) —
never content. See `examples/postmessage-bridge.html` for a working example
and `lib/services/markdown_transfer_protocol.dart` for the wire format.

This stays **opt-in per deployment**: the shipped headers keep
`frame-ancestors 'none'` and `X-Frame-Options: DENY`, so no site can embed
OciDeck — and therefore no site can reach the channel — until you relax them.

**To enable it**, on the OciDeck host:

1. Replace `frame-ancestors 'none'` in the CSP header with
   `frame-ancestors https://your-portal.example` and set
   `X-Frame-Options` accordingly (`X-Frame-Options` only understands
   `ALLOW-FROM` on legacy browsers; frame-ancestors is the real control).
   Keep the rest of the CSP byte-identical.
2. Optionally restrict *which* embedded origins may even ask, by adding
   `trustedMessageOrigins` to `ocideck-web-config.json` (§7):

   ```json
   {"trustedMessageOrigins": ["https://your-portal.example"]}
   ```

   Absent = any site you allow in `frame-ancestors` may *ask* — the user's
   consent dialog is always the real gate. Present = only those origins get
   a `ready` answer; every message still needs explicit user consent.

Notes:
- Only the **iframe** channel is supported (sender = `window.parent`).
  Opening OciDeck in a `window.open` popup cannot work on the default
  deployment: `Cross-Origin-Opener-Policy: same-origin` severs the opener
  relationship, and relaxing it would break the cross-origin isolation that
  local transcription needs — that trade was rejected (see
  `SECURITY_DESIGN.md`, postMessage boundary).
- One transfer per handshake: the sender repeats `ocideck:init` until it
  gets `ocideck:ready`, then sends one `ocideck:open-markdown`. Messages
  before `ready`, after a handled transfer, or with an unknown type/version
  are ignored — the example page implements this retry.
- `Referrer-Policy: no-referrer` does not break this: the app verifies
  `event.origin`, not the referrer.

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

## Release advisory follow-up (2026-11-19)

The v0.7.13 preparation scan produced five advisory groups. They are tracked in
Pawprint as [#3009](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3009),
[#3010](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3010),
[#3011](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3011),
[#3012](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3012) and
[#3013](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3013).

### Public files and cache policy

The HTML, manifest and bootstrap files are public static artefacts, not responses
containing a user's deck, credentials or personalised session. Keep
`Cache-Control: no-cache` on stable filenames: caches may store them but must
revalidate before reuse. An ETag/304 is a valid revalidation. Blanket `no-store`
is not required by the informational ZAP 10015 warning. User data in browser
storage is a separate boundary; these HTTP headers do not control it.

Content-addressed filenames retain `public, max-age=31536000, immutable`.
Unhashed CanvasKit/WASM files must revalidate too. The deployment script retains
older content-addressed files so open tabs can finish loading the matching
application. Verify the actual headers, ETag revalidation, entrypoint bytes and
referenced assets after deployment. A repeat ZAP 10015 informational warning is
accepted for these public responses while this boundary holds; reassess if the
host starts serving personalised or sensitive responses.

### Error-page banners and Apache patch status

The bundle sets `ServerSignature Off` for Apache-generated error pages. Host
administrators must also set **`ServerTokens Prod` at server scope** (it cannot
be set in `.htaccess`). Check the final configuration include order: a later
`ServerTokens OS` or `ServerSignature On` overrides an earlier hardening file.
Validate with `apache2ctl configtest`, reload gracefully, and inspect both a
regular response and real 404 bodies/headers. Do not turn missing files into
200 responses merely to remove an alert.

A banner-only Apache version match is a patch-status investigation, not proof
of an unpatched CVE. Check the distribution release, complete installed package
revision, current security repository candidate and vendor backports. Record
the package/advisory comparison separately from banner suppression; a hidden
version is not evidence that the package is safe. Do not upgrade a shared host
or unrelated services based solely on the upstream banner number.

### CORP and supported resource consumers

The bundled `Cross-Origin-Resource-Policy: same-origin` restricts other origins'
`no-cors` consumption of OciDeck resources. OciDeck's HTML, bootstrap, manifest,
icons and local WASM assets are intended to be consumed from the application's
own origin, including when the whole app is hosted under a subdirectory.
The app's outbound CORS requests and same-origin resources still work. CORP is
separate from COEP (`require-corp`) and COOP (`same-origin`); keep those two
headers for WASM cross-origin isolation.

If a host deliberately publishes an icon or another file for external
`no-cors` use, scope an explicit CORP `cross-origin` override to those shared
files, rather than relaxing the application's whole origin. Review portal and
embedding customisations together with the controls in §8; CORP is not an
embedding allowlist or a replacement for CSP `frame-ancestors`.

### Verification and delivery boundary

Source and built-bundle checks require matching shared CSP directives, with
`frame-ancestors 'none'` added only to the HTTP header. Meta CSP must never
contain that header-only directive. Verify startup, module/WASM loads and the
cross-origin isolation headers alongside a passive baseline. Keep detailed ZAP
evidence rather than just warning counts.

A source fix merged after v0.7.13 is delivered in a subsequent web build; it
does not modify the signed v0.7.13 archive or move its tag. A server-only
configuration change can take effect separately, with its own syntax check,
rollback copy and live HTTP verification.

### Separate CSP subalerts and accepted trade-offs

The baseline groups by scan-rule ID. A single `10055` summary can contain
several alert references; its displayed name is not a complete inventory.
The detailed report separates `10055-11` (invalid meta directive), `10055-3`
(the associated parser notice), `10055-4` (broad `connect-src`) and `10055-6`
(inline style permission). The meta fix removes the first problem and its
notice, without claiming to remove the other two policy trade-offs.

For [#3016](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3016), retain
`connect-src 'self' https: wss: blob:` for user-selected URL import, model/provider
fetches, meeting signalling and local dropped files. A static fixed host list
would remove the supported bring-your-own-provider/host workflow. This leaves
outbound connection opportunities if trusted code is compromised; **CORS does
not prevent sending all requests or act as an exfiltration firewall**. The
controls are a restrictive first-party script policy without inline JavaScript
or general eval, TLS-only external connections, and consent at the relevant
integration boundary. See SECURITY_DESIGN.md §1 for the existing threat model.
A deployment with a fixed set of providers may restrict both header and meta
`connect-src` together. Reassess the generic policy if those workflows change.

For [#3017](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3017), retain
`style-src 'self' 'unsafe-inline'`: Flutter generates runtime styling and the
loading splash uses a local style block. A fixed hash of the splash alone does
not authorise the engine's dynamic styles. This permits injected CSS if markup
injection is introduced; it does **not** authorise inline JavaScript, remote
stylesheets or remote image/font/media loads. The built-bundle gate pins the
style exception separately from the stricter `script-src`. Reassess when the
renderer offers a viable nonce/hash policy for its runtime styles, or when the
app begins rendering untrusted DOM markup.

Both warnings remain enabled in ZAP and are consciously accepted for the
current architecture. Keep the detailed alert references in subsequent scan
reviews, even when the baseline still reports one combined CSP warning group.
