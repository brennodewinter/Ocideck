# OciDeck — Security Design

This document describes the security design principles and the concrete
mechanisms that enforce them. Where a mechanism is implemented, the source is
cited so the claim can be checked against the code — the code is the source of
truth. OciDeck has never tagged a release, so there is no version to which this
description is fixed — it describes the default branch, and details may change;
but the invariants below are enforced by the local `make check` / `make check-full`
gate, not just documented. (The CI workflows are written but no runner executes
them — the repository lives on a Forgejo instance without one, so the local gate
is the real one.)

## Overview

OciDeck has a strong client-side security model with **no application backend**.
The app runs locally on the user's machine (desktop) or in a browser tab (web);
presentation content never leaves the device during editing, previewing,
presenting, or exporting. The only network traffic is explicit and
user-initiated (URL import, WebDAV/Nextcloud, S3, git storage, optional AI), and
each path is individually gated.

## Core principles

1. **File = truth.** Storage stays as close to plain Markdown as possible; there
   is no opaque database and no server that could retain user data.
2. **Zero implicit trust in inputs.** Every deck, asset, and network response is
   treated as untrusted and validated before use.
3. **No egress without consent.** Nothing leaves the machine unless the user
   initiates it; outbound AI in particular is fail-closed (see §7).
4. **Enforced, not just documented.** Security invariants are backed by the local
   `make check` / `make check-full` gates (§2), a compile-time privacy boundary
   (§8), and tests. *(Corrected 2026-07-22: this read "backed by CI gates (§10)".
   §10 is the trusted-internal opt-in and describes no gate, and the CI workflows
   are declared but never executed — the gate is the local one, as the paragraph
   above this list already said.)*

## 1. Web build hardening

The web build is designed to pull **zero third-party origins** at runtime.

- **Strict CSP.** `web/index.html` ships a `Content-Security-Policy` meta tag:
  `default-src 'self'`; `script-src 'self' 'wasm-unsafe-eval'` (no `unsafe-eval`
  / `unsafe-inline`; the wasm token is only for CanvasKit); `style-src 'self'
  'unsafe-inline'` (the Flutter engine injects styles); `img-src`/`media-src`/
  `font-src` first-party plus `data:`/`blob:` only; `connect-src 'self' https:`;
  `object-src 'none'`; `base-uri 'self'`; `frame-ancestors 'none'`
  (`web/index.html:51`). Note a meta-delivered CSP cannot enforce
  `frame-ancestors` — serve it as a real HTTP header to control embedding (see
  [`HOSTING.md`](HOSTING.md)).
- **Self-hosted engine.** `make build-web` builds with
  `--no-web-resources-cdn --csp`, so CanvasKit is served from the same origin
  (never the gstatic CDN) and the bootstrap needs no inline/eval scripts
  (`Makefile:420-425`).
- **Bundled fonts.** The UI font is bundled and registered as `Roboto`, so the
  engine never fetches fonts from `fonts.gstatic.com`.
- **Hardening verifier.** `tool/check_web_hardening.dart` parses the *built*
  bundle and fails the build if any invariant regresses (CSP strictness,
  self-hosted CanvasKit, bundled font). Wired via `make check-web`.

## 2. Supply-chain integrity

- **Pinned, hashed JS bundles.** Every vendored JS/CSS file
  (`marked`, `highlight.js`, `DOMPurify`, `mermaid`, MathJax/`tex-svg.js`) is
  pinned in `assets/web_export/MANIFEST.json` by exact version, sha256, source
  URL, and license. `tool/check_bundled_js.dart` re-hashes each file against the
  manifest and queries the OSV vulnerability database for the pinned versions;
  `make deps-check` fails on a hash mismatch or a known CVE. An offline variant
  (`--offline`, `make deps-verify-offline`) verifies integrity without network
  and runs as a `build-web` prerequisite.
- **SBOM (EU CRA).** `tool/generate_sbom.dart` emits a Software Bill of Materials
  in CycloneDX 1.6 and SPDX 2.3 (plus a human-readable Markdown view) covering
  all direct/transitive Dart packages, the vendored JS/CSS, plugin forks,
  bundled fonts, and pinned SDKs — the artefact required by the EU Cyber
  Resilience Act (Reg. (EU) 2024/2847, Annex I Part II §1). `make sbom-verify`
  is a staleness gate: it fails if dependencies changed without regenerating the
  SBOM, so the CRA artefact can never silently drift.
- **License compliance.** `tool/check_licenses.dart` (`make licenses`) fails if
  any resolved package uses an unrecognised or non-open-source license.
- **Pinned CI Actions.** Third-party CI Actions are pinned to exact versions
  (`.github/pinned-actions.json`); `tool/check_pinned_actions.dart` reports when
  a pin falls behind upstream. The workflows declare least-privilege
  (`permissions: contents: read`, `persist-credentials: false`) and a
  reproducible dependency set (`flutter pub get --enforce-lockfile`) — declared,
  not currently executed, since no runner is attached.

## 3. Network security (NetGuard + pinned transports)

All outbound connections funnel through `lib/utils/net_guard.dart` and a set of
SSRF-pinned transports.

- **SSRF classification.** `isBlockedHost` / `isBlockedAddress` reject loopback,
  link-local, multicast, `0/8`, `10/8`, `127/8`, `172.16/12`, `192.168/16`,
  `169.254/16` (incl. cloud metadata `169.254.169.254`), CGNAT `100.64/10`, IPv6
  `::`, and ULA `fc00::/7`.
- **IPv4-in-IPv6 unwrapping.** `_embeddedIPv4` re-classifies IPv4-mapped,
  IPv4-compatible, and NAT64 (`64:ff9b::/96`) addresses so tricks like
  `[::ffff:169.254.169.254]` and numeric-encoded hosts (`http://2130706433/`)
  can't slip past.
- **DNS-rebind pinning (resolve-then-pin).** `safeResolve` rejects a host if any
  resolved address is internal and returns the validated addresses; callers pin
  the socket to that address via `NetGuard.connectPinned`, so a DNS rebind
  between the check and the connect cannot redirect the socket to an internal
  IP. Redirects are blocked (`followRedirects = false`) at each call site so a
  3xx can't bypass the host check.

  **Pinning and TLS must be set up together.** Setting
  `HttpClient.connectionFactory` makes that factory solely responsible for TLS:
  the SDK's default path calls `SecureSocket.startConnect` with the
  `badCertificateCallback`, but the factory path takes whatever the factory
  returns, verbatim. Returning a plain `Socket` for an `https` URI therefore
  meant *no TLS at all* — requests went out as readable plaintext, including
  the `Authorization` header, and the server answered "the plain HTTP request
  was sent to HTTPS port". `connectPinned` connects to the pinned address and
  then wraps it itself with `SecureSocket.secure(host: uri.host)`, so the
  certificate is validated against the hostname while the socket stays pinned
  to the vetted address. Any new caller must go through it rather than building
  its own factory.

  This is guarded by `test/tls_through_pinned_socket_test.dart`, which reads
  the first bytes off the wire: TLS starts with a `0x16` handshake record,
  plaintext HTTP starts with the method name. The service tests could not catch
  it, because they all speak `http://127.0.0.1` with `trustedInternal`.
- **Self-signed certificates: pinned, never blanket-accepted.** A self-hosted
  server on your own network often has no certificate from a recognised issuer
  — that is the very population `trustedInternal` exists for. Refusing them
  outright shuts that population out; accepting anything self-signed would
  throw the protection away, because a man-in-the-middle's certificate is
  self-signed too.

  So the exception is per-certificate: `pinnedCertSha256` on the connection's
  config holds the SHA-256 of the DER form, and `NetGuard.pinnedCertCheck`
  accepts that one certificate and nothing else. An empty pin yields a `null`
  callback, which means *no exception at all* — the normal issuer chain
  applies.

  The comparison is on the fingerprint alone, not on name, issuer or validity:
  an attacker chooses all three freely. Only the matching private key can
  produce a matching fingerprint.

  The user confirms it in `CertificateTrustDialog`, which shows the fingerprint
  in full and says what to compare it against — the whole point is that the
  user checks it against what their own server reports. Nothing is confirmed
  automatically, and the dialog only appears when the user asks for it after a
  failed connection test.

  When the server later presents a different certificate, the pin no longer
  matches and the connection fails until the user confirms the new one. That is
  deliberate: a renewal and an attacker are indistinguishable from here, so the
  decision belongs to the person who knows the server.

  All three network sources honour a pin — WebDAV, S3 and git — and each of
  their panels can capture one, through a single shared confirmation step: a
  security decision copied three times is two copies too many.

  `test/cert_pinning_test.dart` runs against a real TLS server with a real
  self-signed certificate (generated per run with `openssl`; it is not in the
  repo, and the suite reports itself skipped when `openssl` is absent). It
  asserts that an unpinned self-signed server is refused, that the matching pin
  goes through, that a *different* pin does not, and that a pinned connection
  still validates the hostname.
- **Per-caller byte caps** (see the Performance guide) reject oversized responses
  both by `Content-Length` pre-check and by streaming cap. On desktop both stages
  bite: an oversized `Content-Length` is refused before reading, and the stream is
  aborted mid-download. On **web** the same two-stage check runs, but the default
  browser HTTP client (XHR) buffers the response body *inside the browser* before
  the Dart stream yields anything — so there the `Content-Length` pre-check is the
  effective guard for an honest server, and the streaming cap only bites once the
  client genuinely streams (the Fetch API). A forge that lies about (or omits) its
  `Content-Length` can therefore still make a browser tab buffer an oversized body
  before the cap fires; the cap prevents OciDeck from *retaining* it, not the
  browser from *receiving* it.

## 4. Asset-path containment

Asset references (images, video, CSS) are confined to the project folder by the
functions in `lib/utils/project_path.dart`:

- Absolute paths and `../` escapes are refused on the render/present/export
  paths, so a deck from an untrusted source cannot read files outside its folder.
- `resolveContainedRealPath` / `isRenderPathContained` resolve the **real**
  (symlink-followed) path and refuse a project-internal symlink that points
  outside — a check the lexical `p.isWithin` alone cannot make.
- The distinction between trusted (app-config, e.g. the style-profile logo) and
  editor-permissive resolvers is explicit in the API.

## 5. HTML export sanitization

The HTML export is defence-in-depth against script injection in deck content:

- Every rendered Markdown block is passed through **DOMPurify** before it touches
  the DOM (`lib/services/marp_html_service.dart`), falling back to text if
  DOMPurify is unavailable.
- The exported file carries its **own** CSP with a per-export random nonce
  (`Random.secure`): `script-src 'nonce-…'`, `object-src 'none'`,
  `base-uri 'none'`, `connect-src 'none'`, `form-action 'none'` — so any inline
  script that survived sanitization still cannot execute, and a locally opened
  export cannot beacon home.
- A `</script>` breakout guard neutralises case-insensitive `</script` inside
  inlined payloads, and Mermaid's injected SVG is re-sanitised with DOMPurify's
  SVG profile (Mermaid runs at `securityLevel: strict`). An in-app SVG sanitizer
  (`lib/utils/sanitize_svg.dart`) strips `script`/`foreignObject`/event handlers
  and `javascript:`/`data:` URLs.

## 6. Input validation

- **Structural Markdown pre-flight.** `lib/services/markdown_validator.dart`
  validates front-matter keys against a whitelist, TLP values, comment
  directives, HTML-comment and fence balance, unclosed images/`<video>`/`<audio>`,
  table separators, and embedded chart/cockpit JSON — flagging content that the
  parser would otherwise silently drop.
- **Magic-byte image validation.** `ImageService.imageMimeFromBytes` sniffs
  PNG/JPEG/GIF/BMP/WebP by signature bytes, not by file extension, and import is
  size-capped (64 MiB image / 1 GiB media).

## 7. AI egress control

The optional AI assistant is fail-closed and is the most security-sensitive
subsystem, so it has a dedicated gate.

- **Modes** (`lib/models/ai_settings.dart`): `none` (default — everything off),
  `local` (loopback literal only, pinned directly), `selfHosted` (a user host
  marked `trustedInternal`), and `cloud` (a public endpoint).
- **Pure gate.** `AiSecurityGate.evaluate` (`lib/services/ai_security_gate.dart`)
  is an I/O-free decision run before **every** request by `AiClientService`; a
  denied request throws without touching the network. Cloud requires **both** the
  general outbound-privacy consent **and** a per-destination confirmation, and is
  **blocked entirely on the web build**. Self-hosted requires the explicit
  `trustedInternal` opt-in; local is restricted to a verified loopback address.
- **Key storage.** The optional AI API key is held in the OS keychain
  (`SecretStore`), keyed on the normalised base URL — never in plain config.
- **System guardrail.** Requests carry a system guardrail prompt and send only
  the caller-supplied field/context (e.g. one image for alt-text, one finding for
  a suggestion), not the whole deck.
- A stricter privacy projection, `PrivacyProjection.forExternalProcessing`
  (which ignores per-slide disposition and redacts everything the scanner finds),
  exists in the privacy layer as a reusable primitive for external hand-off.

## 8. Privacy protection (OciWacht)

`lib/services/privacy/` implements the privacy scanner and the redaction/audience
model.

- **Rule families.** Contact data (`email`, `phone`, `address`/`postcode`,
  `name`), financial (`iban`, checksum-validated), Dutch `bsn` (11-proof +
  context), secrets (vendor tokens, private keys, JWTs, plaintext passwords),
  national identifiers for 13 EU member states plus two UK ones (15 rules in
  total), GDPR Art. 9 special-category keywords, and
  structural leaks (user paths, tokens-in-URLs, `mailto:`/`data:` URIs).
- **Deliberately non-NER names.** Name detection only fires behind a
  salutation/label (`dhr.`/`mevr.`/`naam:`) and stays a *possible* finding — a
  bare capitalised word is intentionally not flagged.
- **False-positive engineering.** Checksums, placeholder/allowlist registries,
  own-identity suppression, and masked samples in findings (never the raw value).
- **Redaction as a value transform.** `PrivacyProjection` replaces sensitive
  content with a **fixed-width** block token (not the original length, to prevent
  reconstruction) *before* the deck reaches any surface; manual `[[…]]` markers
  always redact.
- **Type-enforced boundary.** Only `PrivacyProjection` can construct an
  `AudienceDeck` (private constructor). A `check_conventions` gate
  (`audienceBoundary`) fails the build if any receiving/export surface accepts a
  raw `Deck`/`List<Slide>` instead of an `AudienceDeck` — the privacy boundary is
  enforced at compile time, not by convention.

## 9. Classification, integrity & secure storage

- **TLP classification gate.** `ClassificationEnforcementPolicy.evaluate`
  (`lib/services/classification_enforcement_policy.dart`) is a fail-closed export
  gate with a release ceiling, a required floor, and an optional
  "block unclassified" rule; it runs on `ExportService.export`.
- **Classification watermark.** When enabled, the TLP level is stamped onto
  rasterized PDF/PPTX output (`SlideRasterizer`) and rendered as a banner in HTML
  export.
- **Document integrity seal.** `lib/services/document_integrity.dart` computes a
  **SHA-512** seal over a deck's canonical Markdown content; `verify()` reports
  `intact` / `changed` (tamper-evidence, not tamper-proofing), and
  `verifyRedactedDerivative()` reconciles a redacted export against its sealed
  source via the redaction manifest so a legitimate redaction is not a false
  alarm. An optional `DocumentSignature` is folded into the seal. Related
  audit-value tooling exists for the pentest module: RFC 3161 timestamp tokens
  (`rfc3161_timestamp.dart`), evidence hashing (`evidence_hash_service.dart`),
  and an audit dossier (`audit_dossier.dart`). The timestamp handling is
  deliberately shallow: `timeStampMatchesHash` compares the token's message
  imprint with the seal hash and stops there — no CMS signature, no certificate,
  no chain. It shows that *this* token was issued over *this* hash, not that a
  trustworthy authority issued it. Calling it a "trusted timestamp" overstated
  that; *corrected 2026-07-21*.
- **Encrypted packages.** `.ocideck` packages can be encrypted
  (`lib/utils/zip_encryption.dart`, wired into `FileService`); an encrypted
  package cannot be opened without its password.
- **Atomic writes.** All persistence uses `writeStringAtomic`/`writeBytesAtomic`
  (`lib/utils/atomic_file.dart`) — write-to-temp-then-rename — so a crash never
  truncates a file. A `check_conventions` ratchet forbids raw
  `writeAsString`/`writeAsBytes` anywhere else.
- **Secret storage.** WebDAV/Nextcloud passwords, the S3 secret access key, the
  AI API key, and the git personal-access token live in the OS keychain via
  `flutter_secure_storage` (`lib/services/secret_store.dart`), keyed per
  server/account; only the secret goes there — URLs, usernames and the S3
  **access key ID** stay in the prefs domain. The git token leaves the keychain
  for the lifetime of a `git` subprocess, passed via `GIT_CONFIG_*` so it reaches
  neither argv, nor the remote URL, nor `.git/config`
  (`lib/services/git/native_git_mirror_io.dart`).
- **Git working copies.** A native clone (`git_clone/<storageSlug>/`), a draft
  mirror (`git_mirror/<storageSlug>/`) and the pending-commit outbox hold full
  deck content under app-support. They are **not** encrypted and — unlike
  recovery snapshots — have **no** expiry, since a working copy is meant to
  survive between sessions.
- **Recovery snapshots** are written atomically to a per-user app-support
  directory, are **not** encrypted (they inherit OS user-account file
  protections), and are pruned after 7 days.

## 10. Trusted-internal opt-in

WebDAV/Nextcloud, S3, git, and self-hosted AI each expose an explicit
`trustedInternal` flag — for S3 it is what makes a MinIO box on the LAN usable. Only when the user sets it does
`NetGuard.safeResolveTrusted(host, allowPrivate: true)` relax the private-range
block (still resolving and pinning), and only then is plain `http` accepted for
that user-configured host (so a token isn't sent in the clear on a TLS-less
internal box). Deck-supplied URLs never reach this relaxed path.

**The native git path gets the same guarantees by a different mechanism.**
`clone`/`fetch`/`push` run in a `git` subprocess, so there is no socket of ours
to pin. Instead `native_git_mirror_io.dart` imposes the outcome: the approved
address is bound to the hostname with `http.curloptResolve` (TLS still validates
the name), redirects are refused with `http.followRedirects=false` — the token
rides along as `http.extraHeader`, and headers follow redirects — and the same
`https`-unless-trusted-internal rule applies. `file://` is exempt as it never
reaches the network; other schemes are refused. Verified in
`test/git_network_guard_test.dart`, which also checks that `git` honours the pin
rather than assuming it.

A pinned certificate is translated the same way. Git has no notion of a
certificate fingerprint — only a CA file — so `native_git_mirror_io.dart` fetches
the certificate at the pinned address, compares the SHA-256 itself, and only then
writes it out and points `http.sslCAInfo` at it. The decision stays on our side:
git never sees anything that was not first checked against the recorded
fingerprint. `http.sslVerify` is deliberately **not** disabled — that would drop
chain *and* hostname validation and make the pin meaningless; with a CA file git
keeps validating normally and this one certificate is simply a valid anchor.
Because `badCertificateCallback` on the REST path only fires when normal
validation fails, a pin means "trust this certificate *as well*", not "trust only
this one" — the native path matches that.

## 11. Offline reference data (MIAUW pentest module)

The opt-in "Informatieveiligheid" (pentest reporting) module keeps all reference
data local:

- **Offline CWE catalog.** A curated in-repo floor plus the full MITRE CWE list
  bundled as an asset (`assets/cwe/cwe_full.json`, generated offline by
  `tool/build_cwe_catalog.dart`) — no runtime network; entries link back to
  cwe.mitre.org.
- **Local CVE database (desktop).** Built into the app-support directory from a
  GitHub bulk-release archive via an SSRF-hardened transport that re-resolves and
  re-pins the socket on every redirect hop (max 5, https-only). Live CVE lookups
  use the 2 MiB-capped `PinnedCveTransport`.

## 12. Cryptography in one table

*Added 2026-07-22.* Every algorithm below was already documented somewhere — in
[`FILE_FORMAT.md`](FILE_FORMAT.md) §7.1, in §9 and §10 above, or only in a source
comment. Spread out like that, the two questions a reviewer actually asks ("what
is used where" and "what does it not protect") could not be answered without
reading four files. This table is the single answer; each row cites where it
lives so it stays checkable.

| Algorithm | Size | Where | What it protects | What it does **not** protect | Rotation |
| --- | --- | --- | --- | --- | --- |
| **AES-256**, WinZip AE-1 | 256-bit key | `.ocideck` package export/import (`ZipEncoder(password:)`, `lib/utils/zip_encryption.dart`) | The **contents** of every file in the package | **File names and structure** — the central directory is not encrypted, so a chart's data file still names its chart. Nor does it authenticate the archive as a whole | Re-export with a new passphrase; there is no re-key of an existing package |
| **PBKDF2-HMAC-SHA1** | 1000 iterations | Key derivation for the above, inside `package:archive` | Turns a passphrase into the AES key | Nothing, on its own. 1000 iterations is low by any modern standard, and it is **fixed by the WinZip AES specification** — not reachable from OciDeck at any price. A short passphrase is the weak link, which is why the export dialog shows an entropy meter and offers a generator | n/a |
| **HMAC-SHA1, truncated to 80 bits** | 10 bytes | The AE-1 authentication tag, verified on decrypt | That the ciphertext was not altered | 80 bits is the format's choice, not ours; it is an integrity tag, not a document signature | n/a |
| **SHA-512** | 512-bit | The document seal (`lib/services/document_integrity.dart`), and the imprint in an RFC 3161 request (`rfc3161_timestamp.dart`) | **Tamper-evidence**: a sealed deck that changed reports `changed` | Tamper-*proofing*. Anyone who edits the deck can recompute the seal — it proves change, not authorship. See §9 | Recomputed on every finalise |
| **SHA-256** | 256-bit | Certificate pinning (`NetGuard.pinnedCertCheck`, over the certificate's DER form); git asset-pool filenames (`asset_pool.dart`); evidence hashes; the SBOM's component hashes | That you are talking to the machine you confirmed, and that two files are the same file | A pin means "trust this certificate **as well**", not "only this one" — see §10. A renewed certificate looks exactly like an attacker from here, which is why re-confirmation is a human step | The user re-confirms the fingerprint when the server's certificate changes |
| **SHA-256, salted commitment** | 128-bit salt per redaction | Redaction manifest (`privacy/redaction_manifest_service.dart`): `sha256(salt ‖ 0x00 ‖ value)` | Lets an author prove afterwards what a single redaction hid, **without** revealing the others (selective disclosure) | It is a commitment, not encryption. The salt is what stops a nine-digit value being brute-forced back in seconds, so the copy that travels with a redacted export carries **no** salts (`RedactionManifest.withoutSalts`) | A new salt per redaction, per build of the manifest |
| **SHA-1** | 160-bit | Evidence hashing, **alongside** SHA-256 (`evidence_hash_service.dart`) | Nothing that SHA-256 does not already do | It is present because the **MIAUW methodology prescribes SHA-1** in its evidence tables, and a report that omits it does not meet the method. It is never used alone and never used for a security decision | n/a |
| **MD5** | 128-bit | Duplicate-image detection (`image_dedup_service.dart`) | Nothing — this is **not a cryptographic use.** It groups byte-identical images in one session so the UI can offer to deduplicate them | Everything. The comparison is ephemeral, never written to a durable name, and an attacker who collides it achieves nothing but a wrong grouping in their own deck. Recorded as decision D1 in [`design/GIT_STORAGE.md`](design/GIT_STORAGE.md) §14 | n/a |
| **CSPRNG** (`Random.secure`) | 128-bit nonce; 128-bit salt; 32/256-char passphrase | The per-export CSP nonce (`marp_html_service.dart`), redaction salts, the passphrase generator (`utils/password_generator.dart`) | The nonce is what makes the HTML export's CSP meaningful: only scripts we emitted carry it, so injected inline script cannot execute | A nonce is per export, not per session — two exports of the same deck differ here, which is intended | New value per export / per redaction / per generated passphrase |

**A generated passphrase is ASCII, and that is not an accident.**
`passwordAlphabet` in `utils/password_generator.dart` is printable ASCII without
quotes, backslash or space. Section 7.1 of [`FILE_FORMAT.md`](FILE_FORMAT.md)
explains why a hand-typed non-ASCII passphrase is a problem for the ZIP format
itself; a generated one never runs into it.

### `DocumentSignature` contains no cryptography

Worth its own heading, because the class name sends every reader down the wrong
path. `DocumentSignature` (`lib/models/document_signature.dart`) is a **visual
sign-off block**: a name, a role, a certification, a date, a statement, a typed
name, and optionally a path to an image of a handwritten signature. That is all
of it. There is no key, no certificate, no signing operation, and nothing in it
can be verified by anyone.

What it *does* have is a relationship with the seal: when a deck is finalised,
the signature block is folded into the SHA-512 seal over the canonical content
(§9), so altering the signed statement afterwards makes the seal report
`changed`. That is tamper-evidence over the block, which is a genuinely useful
property and a different one from a digital signature. Nobody can tell from the
document *who* sealed it.

If a report needs a signature in the legal sense, it needs something this project
does not implement, and the RFC 3161 timestamp support is not it either — that
proves *when* a hash existed, and only as far as the token's message imprint,
since the TSA's own CMS signature is deliberately not verified (§9).

## 13. Key management

*Added 2026-07-22.* Four kinds of secret exist. None of them is a key OciDeck
generates and keeps for itself; every one is either the user's, or the operating
system's, or thrown away after a single use.

| Secret | Held by | Reachable by | If it is compromised |
| --- | --- | --- | --- |
| **Package passphrase** | Nobody but the user. It is never stored, never cached, and never written to preferences or the keychain — it exists in memory for the duration of one export or one open | The user, and whoever they give the package to | Every copy of that package that was ever handed out is readable. There is no revocation and no re-key: re-export with a new passphrase and treat the old package as public |
| **Storage credentials** — WebDAV/Nextcloud app password, S3 **secret** access key, git personal-access token, AI API key | The OS keychain, via `SecretStore` (`flutter_secure_storage`), keyed per server plus identity: `webdav_pw::…`, `s3_secret::…`, `git_pat::…`, `ai_api_key::…` | The app, and anything else running as that OS user with keychain access | Revoke it at the server, not here. Removing the connection in OciDeck rewrites preferences and **does not** delete the git working copy, mirror or outbox — see `SECURITY.md`, *Crash-recovery snapshots*. The git token additionally leaves the keychain for the lifetime of each `git` subprocess (§10) |
| **Pinned certificate fingerprint** (SHA-256) | Preferences, in the clear — `pinnedCertSha256` on `S3Settings` / `WebdavSettings` | Anyone who can read the preferences file | It is not a secret; publishing it costs nothing. The risk runs the other way: an attacker who can *write* preferences can pin their own certificate, so the integrity of that file is what matters, not its confidentiality |
| **Per-export CSP nonce and per-redaction salt** | Nowhere. Generated, used once, discarded — except that redaction salts are kept in the author's own manifest so a redaction can be proved later | The author, and the export they produced | A leaked salt lets someone brute-force that one redacted value. That is why the manifest that travels with a redacted export is the salt-free one |

Two things this table deliberately does not claim. The keychain is as strong as
the OS account it lives in: an attacker who is already that user does not need to
break it. And the S3 **access key ID** is stored in preferences in the clear —
it is an identifier, not a password, but it names the account to anyone who reads
that file.

## 14. What is logged

*Added 2026-07-22.* A short section because there is little to describe, which is
itself the point.

**Where it goes.** Everything routes through `logError` / `logWarning` in
`lib/utils/log.dart`, which calls `dart:developer`'s logging stream. That stream
is read by DevTools and the VM service. It is **not stdout**, so a release build
prints nothing, and there is **no log file**: OciDeck writes no log to disk, ships
no log rotation, and has nothing to configure. Attach a debugger and you see the
records; do not, and they go nowhere. A `check_conventions` ratchet forbids raw
`print()` anywhere in `lib/`, so this is the only route.

**What is in a record.** An operation description (`'openDeck: read annotation
sidecar'`), a severity — 900 for a handled fallback, 1000 for an unexpected
failure, mirroring `package:logging` — and the caught error object. Deck content
is **not** logged, by rule and by mechanism. The rule is the doc comment on that
file: pass an operation description and the error, never file or deck contents.
The mechanism is `_safeError`, and it exists because the rule alone was not
enough: `FormatException.toString()` embeds a slice of the text it failed to
parse, and `jsonDecode` sets that text to exactly what was being parsed — so a
malformed slide field wrote the slide's content, special-category personal data
included, into the log while every call site was obeying the rule. `_safeError`
reduces a `FormatException` to its message and offset and drops the rest.

**Retention and access.** None and none, respectively: there is nothing to
retain, so there is no retention period, no purge, and no access control to
describe. The one exception is not a log at all — crash-recovery snapshots, which
*do* hold full deck content in plaintext under app-support and are pruned after
seven days. They are documented in `SECURITY.md` under *Crash-recovery
snapshots*, and they are the thing to look at when the question is really "what
of my deck is on this disk".

## Standards this design draws on

Read as influences on the design, not as a conformance statement — this section
claims no certification and no compliance (*reworded 2026-07-21*).

- **SBOM formats.** The bill of materials is emitted in CycloneDX 1.6 and SPDX
  2.3 and held current by a staleness gate (§2), so it is machine-readable for
  whoever needs it.
- **GDPR thinking.** Data minimisation (no telemetry), processing on the device,
  and the OciWacht scanner/redaction model (§8).
- **Defence in depth.** Layered guards rather than a single boundary: the SSRF
  guard, the import caps, path containment, the projection boundary.

**"Fail-closed" is per mechanism, not a blanket default.** Several mechanisms do
fail closed once they are switched on — the classification gate writes no file
when a rule blocks, the SSRF guard refuses rather than falls back, an import over
its cap is rejected. But the security-relevant *defaults* are mixed, and it is
worth naming which is which: the privacy check is on by default, remote media,
the AI backend and the CVE lookup are off by default, and the classification
enforcement is **entirely off** by default (`maxReleaseExportTlpKey` and
`minRequiredExportTlpKey` are null and `requireClassificationOnExport` is false
in `AppSettings`). A deck therefore exports without any classification
constraint until an organisation configures one, which is a deliberate choice —
a gate nobody asked for is a gate that gets worked around — but it means "fail-closed
defaults" was the wrong summary. *Corrected 2026-07-21.*

## Threat model

**Assumptions.** The user's machine is trusted (not malware-compromised);
networks are usable but not trusted; files from third parties are untrusted.

**Primary vectors, mitigations and what is left.** The table gained its last two
columns on 2026-07-22. Before that it listed risks and controls but no residual
and no owner, which reads as if every risk were closed — and none of these is.
The date in the last column is when the residual was accepted in the form stated
here; a residual with no date is one nobody has looked at, and there should not
be any.

| Risk | Mitigation | Residual risk | Accepted on |
| --- | --- | --- | --- |
| **Malicious deck or asset** | Structural validation (§6), asset-path containment (§4), HTML-export sanitization (§5), magic-byte image checks (§6), bounded image decoding | The render-path symlink cache is keyed by path for the session, so a symlink swapped *after* its first render is not re-checked — a narrow TOCTOU on an already-open deck (also stated in `SECURITY.md`) | 2026-07-22 |
| **Network / SSRF** | NetGuard classification, resolve-then-pin, no redirect following, byte caps (§3); trusted-internal is opt-in (§10) | Live media rendering (`NetworkImage`, the video controller, the embed WebView) does its own DNS and cannot be socket-pinned, and a positive host resolution is cached for the session. This is why online media is **off by default** and scoped to sessions the user enables (§7 of `SECURITY.md`) | 2026-07-22 |
| **Data exfiltration via AI** | Fail-closed egress gate, dual consent for a cloud backend, blocked on web (§7) | The gate governs what OciDeck sends. What the configured backend then does with it is outside this design entirely — a self-hosted model and a cloud API get the same bytes and offer different guarantees, and only the user knows which they configured | 2026-07-22 |
| **Tampering with a finalised report** | SHA-512 seal over canonical content, with the sign-off block folded in (§9, §12) | Tamper-**evidence**, not tamper-proofing: anyone who edits the deck can recompute the seal. It shows *that* something changed, never *who* sealed it. An RFC 3161 token adds *when*, and only as far as the message imprint — the TSA's own signature is not verified | 2026-07-22 |
| **Supply-chain drift** | Hashed and OSV-checked export bundles, SBOM staleness gate, licence and pinned-action gates (§2) | The Dart package graph is scanned only advisorily (`make trivy` never fails, by configuration), because pub advisory coverage is sparse. Two bundled components carry named, deferred items — mermaid 10.9.6 and MathJax 3.2.2 — recorded in `SECURITY.md` | 2026-07-22 |
| **Deck content at rest on the machine** | Recovery snapshots are pruned after 7 days; the app-support directory carries OS user permissions | Snapshots and git working copies are **unencrypted**, and a git clone additionally keeps full history with no expiry. Removing the connection does not remove them. Encrypting snapshots at rest is a known, unimplemented improvement | 2026-07-22 |
| **A compromised or hostile operating-system account** | Out of scope, by the assumption above | Everything. The keychain, the snapshots, the working copies and the preferences all trust the OS account. On macOS the App Sandbox is deliberately **off**, so there is no OS-level process isolation either (`SECURITY.md`, *Platform sandboxing*) | 2026-07-22 |

Every row's mitigation cites a section that names the code; every residual is
stated somewhere else in this repository too, and the wording here is meant to
match it. Where this table and the section it points at disagree, the section is
the more detailed one and wins.

## Roadmap

Planned hardening includes more granular privacy controls in export settings and
continued expansion of the offline reference data. (Encrypted package export,
previously listed here as future work, has shipped — see §9.)
