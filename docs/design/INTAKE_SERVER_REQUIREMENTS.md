# OciDeck — Intake server: requirements

> **Status:** requirements for the intake server of phase 4 of [`FORM_INTAKE.md`](FORM_INTAKE.md) — **the server is not built** · **Status last reviewed:** 2026-10-03 · **Published by:** Stichting LibreKAT
>
> **Licence:** this document is **CC-BY-4.0**, like [`INTAKE_PROTOCOL.md`](INTAKE_PROTOCOL.md) (D5). A third party may build a
> compatible server from the two documents and the CC0 test vectors alone.
>
> **Who this is for.** The person who will maintain the server (FORM_INTAKE.md §14, D3 — nobody is named yet), whoever
> operates one, a reviewer, and whoever writes a different implementation. It says **what the server must do and must
> not do, and what its operator must promise**. It does not say how to build it; the contract on the wire is
> [`INTAKE_PROTOCOL.md`](INTAKE_PROTOCOL.md), and this document does not repeat it — it says what the server must make
> true *around* it. [§6.5 of the design](FORM_INTAKE.md) holds the minimum bar in a handful of lines; this is that bar, written
> out so it can be tested.

---

## 0. How to read this

- **MUST**, **MUST NOT**, **SHOULD**, **MAY** are used as in RFC 2119. A server that does not meet every MUST is **not
  conformant**, and must not be offered to respondents as an OciDeck intake server.
- Every requirement has an **id** (`PRO-03`, `SEC-07`), so that a conformance suite, a review finding or an operator's
  checklist can name it. Ids are never reused; a withdrawn requirement keeps its id and says so.
- A requirement marked **(reference)** binds the reference server and a hosted deployment of any server; a server that
  someone runs for themselves may choose otherwise, and says so.
- **Why** follows where the reason is not obvious. A requirement without a reason that survives a week is a candidate
  for deletion.

## 1. What the server is — and the lines it does not cross

The server is a **dropbox for ciphertext** (INTAKE_PROTOCOL.md §1). It stores sealed packages and a little metadata,
it lets organisers collect them, and it is trusted with **nothing but availability**. The seven conditions of
FORM_INTAKE.md §2.1 are the server's conditions too; the ones that bind the *server* are these requirements. If any of
them fails, §2.1 re-opens with the owner.

| Id | Requirement |
|---|---|
| **PRI-01** | The server **MUST NOT** read, parse, decompress, scan, thumbnail, index or transform the contents of an uploaded package. It handles opaque bytes. (A refused mode, FORM_INTAKE.md §6.8: a server that reads plaintext is a backend and ends condition 3.) |
| **PRI-02** | The server **MUST NOT** have accounts, sessions or cookies, and **MUST NOT** keep an identity of a respondent. The respondent is a token and a random number. |
| **PRI-03** | The server **MUST NOT** serve the web form shell, nor any code that runs in a respondent's browser. Code that sees plaintext must not come from the party that stores ciphertext (condition 3). |
| **PRI-04** | There **MUST NOT** be a default server address in OciDeck, and the foundation **MUST NOT** operate an intake server for others (FORM_INTAKE.md §9.3). A deployment that serves the shell and the server from one operator **MUST** say in its documentation that this operator can read web respondents' input. |
| **PRI-05** | The server **MUST NOT** emit anything to a third party: no analytics, no error reporting service, no font or script from elsewhere, no call home, no update check. Its only outbound traffic is what its operator configures for operating it (certificates, backups). |

## 2. Conformance to the protocol

The protocol is normative; these are the properties a server has to *demonstrate*.

| Id | Requirement |
|---|---|
| **PRO-01** | Every path, method, status, header, body and error code is as in INTAKE_PROTOCOL.md §§2–6. The routes are read with the strict grammar of §2 (`matchIntakeRoute` in `ocideck_form_core` is the reference): one spelling of every request, decided in the order shape → method → id → query. |
| **PRO-02** | A *request* member the server does not know is refused with `bad-request`; a *response* the server sends carries only members the protocol names (it may add one, additively, within a version — §9 of the protocol). |
| **PRO-03** | Uploads are checked in the order of INTAKE_PROTOCOL.md §4.3: ids, `Content-Length` and the cap **before a byte is read**, form, token, closed, rate, then the stream. A refusal that comes earlier in the order **MUST** win over one that comes later. |
| **PRO-04** | `PUT /v1/submissions/{sid}` is **idempotent** and **never overwrites**: the same `sid`, the same form and the same ciphertext hash gives `200` and the **same arrival note** (the same `at`); anything else under a held `sid` is `409 submission-conflict`. This holds across a restart. |
| **PRO-05** | The arrival note's `ciphertext_sha256` **MUST** be the hash of the bytes the server actually stored, computed while streaming. |
| **PRO-06** | Every response carries `Cache-Control: no-store` and the right `Content-Type`. Every error is the JSON body of §6 with a code from the closed set; a refusal the protocol does not name is the nearest named one, never an invented code. |
| **PRO-07** | The server **MUST NOT** follow, issue or accept a redirect as part of the protocol. A request for a path that exists on `http` goes nowhere (SEC-01). |
| **PRO-08** | `GET /v1/info` is truthful: `protocol` is the version the server speaks, `limits.max_package_bytes` is the cap it enforces, `source_url` points at the source that is running (SUP-01), `operator_contact` is a line a person reads. |
| **PRO-09** | A server speaking several protocol versions answers each on its own path prefix and never mixes their bodies. |
| **PRO-10** | **Withdrawal** answers as INTAKE_PROTOCOL.md §4.4: a wrong secret and an unknown `sid` are the same `404 submission-unknown` (no oracle); a repeat of a recorded withdrawal is `200` with the first `at`; a withdrawal after the form closed is accepted. The comparison of the hash **MUST** be constant-time. |
| **PRO-11** | The listing is stable under concurrent writes: a page never skips or repeats a submission that existed for the whole walk, and a cursor is opaque and unforgeable into another form's data. |
| **PRO-12** | `DELETE` and the purge remove the **ciphertext and its metadata together**, durably (STO-04); a `GET blob` after either is `404`. |

## 3. Authentication and authorisation

| Id | Requirement |
|---|---|
| **AUT-01** | Organiser requests are verified as INTAKE_PROTOCOL.md §5.1, **in that order**: well-formed header → window → signature (over the host, method, target and body hash **as the server knows them**, never as the header claims) → authorisation → nonce. A nonce is recorded **only** after the first four pass, so that a stranger signing with their own key cannot fill the cache. |
| **AUT-02** | The `host` that is verified is the server's own **configured public host**, not the `Host` header it was reached by (a proxy may rewrite it). The same string is the `policy.api_host` every published bundle must carry. |
| **AUT-03** | The window is five minutes either way; the server's clock **MUST** be disciplined (NTP) and the server **SHOULD** refuse to start, or say so loudly in its health check, when it cannot tell that it is. A clock a day out locks every organiser out and lets old requests through. |
| **AUT-04** | The nonce cache holds `(key, nonce)` for as long as the request could still verify, and answers `rate-limited` rather than forget a nonce that still counts. A server run as **more than one instance** **MUST** share the cache between them, or not run as more than one instance: a replay to the other instance is a replay. |
| **AUT-05** | **A new `fid` is accepted only from a key on the operator's allowlist**, and only if that key is the owner of the bundles in the body. An existing `fid` is updated only by its owner key. Without this the server is an anonymous 120 MiB-per-request storage service and a squatting target. |
| **AUT-06** | Authorisation follows the table in INTAKE_PROTOCOL.md §5.2, from the **current** bundle (highest `bundle_seq`): the owner for publishing and the token; any listed organiser for list, blob, `ack` and `DELETE`. A departed organiser — absent from the current bundle — **loses access at the moment** the new bundle is published. |
| **AUT-07** | Invite tokens are stored **only as hashes** and compared in constant time. The server never learns a token except in the header of an upload, and never logs it. A rotation or revocation takes effect for the **next** request. |
| **AUT-08** | The operator's allowlist is a file the operator edits; the server **MUST NOT** offer a way to change it over the network. Removing a key from it stops that key creating forms; it does not delete forms it created. |

## 4. Publishing: what the server verifies

| Id | Requirement |
|---|---|
| **PUB-01** | The server runs the whole of FORM_INTAKE.md §5.1 on every bundle in a publication, against the template that came with it and the fingerprint of the key that signed the request (`verifyFormBundle` in `ocideck_form_core`). A bundle that does not verify is `bundle-invalid`; the publication is refused **as a whole**, nothing is stored. |
| **PUB-02** | Every bundle's `fid` is the path's and its `policy.api_host` is this server's public host (`bundle-host-mismatch`). |
| **PUB-03** | Every variant of one publication carries the **same `bundle_seq`**, and none is lower than the highest the server holds for the form (`bundle-rollback`, `409`); equal is accepted, so that re-publishing is idempotent. |
| **PUB-04** | A publication replaces the previous set **atomically**: a respondent fetching during a publication gets the old set or the new one, never a mixture. |
| **PUB-05** | The limits of INTAKE_PROTOCOL.md §4.2 are enforced on the way in: at most 32 variants, a bundle of at most 256 KiB, a template of at most 1 MiB counted in bytes, the body at most 8 MiB. |
| **PUB-06** | The server **MUST NOT** believe a bundle's `expires` or `closes` to decide anything the signature does not cover. It **MAY** use the signed `closes` day to refuse uploads after it (the last day is still open) and **MUST** treat the owner-set `state` as authoritative for refusing uploads. |

## 5. Storage, durability and retention

| Id | Requirement |
|---|---|
| **STO-01** | A submission becomes **visible** (to a listing, to `GET blob`, to an idempotent retry) only when its ciphertext is complete and durably written. A crash or a cut connection mid-upload leaves **no** partial submission and **no** `sid` that refuses a retry. |
| **STO-02** | The ciphertext is written to a temporary name and renamed into place after `fsync`; metadata and ciphertext agree after any crash. A disk that is full answers `503 unavailable` (or `413` when the cap is the cause) and **never** a stored truncated blob. |
| **STO-03** | The ciphertext is stored **byte for byte**. The server adds no header, no framing, no compression and no encryption of its own that changes what `GET blob` returns. |
| **STO-04** | Deletion (`DELETE`, the purge, a withdrawal) removes the bytes from the data directory and the metadata from the database; the operator's documentation states plainly what a backup still holds and for how long (OPS-05). |
| **STO-05** | **Retention.** A ciphertext is purged when **every organiser in the current bundle has acknowledged it**, or — the hard cap — **90 days after the form closes** (the owner closing it, or its `closes` day passing), whichever is first. These are the defaults; the operator **MAY** lower them, **MUST NOT** raise the hard cap, and the bundle policy and the acceptance dialog show what the respondent is promised. |
| **STO-06** | **Tombstones.** A withdrawal leaves `{sid, at, hash of the secret}`, kept **24 months**, so that a withdrawal whose answer was lost can be repeated. It is the only metadata that survives a purge. |
| **STO-07** | The server keeps **no** second copy of a submission outside its data directory and its documented backups: no cache, no queue, no log of the body. |
| **STO-08** | Metadata is **minimal**: `sid`, `fid`, size, hash, arrival time, the acknowledging `kid`s, the withdrawal hash. No name, no address, no user agent, no truncated IP stored with a submission. |
| **STO-09** | The storage engine's own integrity check **MUST** run at start-up and the server **MUST** refuse to serve from a store it cannot vouch for, rather than serve an empty one (a respondent would then get `submission-unknown` for something that was merely unreadable). |

## 6. Abuse resistance and limits

A malicious respondent is the normal case for an open link in a forwarded group chat. The server's job is to remain
useful to the honest ones (FORM_INTAKE.md §9.1).

| Id | Requirement |
|---|---|
| **LIM-01** | **A hard byte ceiling, enforced while streaming**: the request is cut at the cap, **never buffered whole in memory**, and a declared `Content-Length` over the cap is refused before the first byte is read. A body longer than it declared is `too-large` and the connection is closed. |
| **LIM-02** | **Caps are per token per time window, not one absolute cap per form.** A single absolute cap *is* the denial-of-service tool: someone fills it and real respondents get "form closed". The server counts uploads and bytes per token and per window. |
| **LIM-03** | A **rate limit per network bucket** (an IPv4 /24, an IPv6 /48 — truncated, never the full address, LOG-02) and per token, answering `429` with `Retry-After`. |
| **LIM-04** | Time limits on **every** phase: reading the request line and headers (seconds), reading the body (a floor of bytes per second, so a slow loris dies; a total ceiling that fits a 120 MiB upload on a slow line), writing the response. A connection that does nothing is closed. |
| **LIM-05** | A bound on **concurrent uploads** and on concurrent connections per bucket, so that a few slow clients cannot hold every worker; a bound on header size and on the number of headers. |
| **LIM-06** | The operator can see — in the organiser's listing or the health check — that a cap or the disk is near its limit; **the organiser is warned at 80 %** of any cap (FORM_INTAKE.md §6.3). *Open: the wire does not yet carry this; see §13.* |
| **LIM-07** | A disk quota per form and a total, configurable; when the total is spent the server refuses new uploads (`503`) and **still serves organisers** (list, blob, `ack`, `DELETE`): collecting must be possible exactly when the disk is full. |
| **LIM-08** | The organiser can **delete without fetching** (`DELETE`), and **rotate the token** (`PUT …/token`) to end a link that spread: both effective at once. |
| **LIM-09** | Reasonable defaults, proposed for the reference server and **overridable downwards** by the form's policy: per token 200 uploads per 24 hours; per network bucket 20 uploads per hour; at most 8 concurrent uploads; a floor of 32 KiB/s while reading a body; a header read within 10 seconds. These are starting points to be tuned on real use, not promises. |

## 7. Privacy and logging

The operator of the server is a **processor** of ciphertext and metadata (FORM_INTAKE.md §9.3); the organiser is the
controller. The server must make that role honest.

| Id | Requirement |
|---|---|
| **LOG-01** | **No request body, no `Intake-Token`, no `Intake-Withdrawal`, no withdrawal secret, no `Authorization` header** appears in any log, metric, trace, crash dump or error report, at any level, ever. |
| **LOG-02** | The application keeps **no full IP address** beyond a short-lived, truncated form for rate limiting (an IPv4 /24, an IPv6 /48, held for the length of the longest window and then dropped). |
| **LOG-03** | The **reverse proxy is part of the threat surface** — it terminates TLS. **(reference)** The server ships a proxy configuration with the access log **off or IP-truncated** and rotation of **at most 7 days**, and its documentation states plainly that **without it the operator sees full IP addresses**. |
| **LOG-04** | Logs say *what happened*, not *to whom*: an event, a status, a duration, a **pseudonymous form id prefix at most**. A log line never contains a `sid` together with a time that could join it to a person's message. |
| **LOG-05** | **Metrics carry no per-form or per-token label.** Counters are server-wide (uploads, refusals by code, bytes, purges). A per-form series is a map of who is running which call. |
| **LOG-06** | The server sets **no cookie**, sends **no** `Set-Cookie`, **no** `Server`/version banner that names the build, and **no** tracking-capable header. |
| **LOG-07** | Operator documentation states: what the server stores (STO-08), what its proxy sees, the retention (STO-05, STO-06), that the **bundle is plaintext on the server** (template, organisers' public keys, policy — INTAKE_PROTOCOL.md §8), and that a form whose existence is sensitive must not use a guessable `fid`. |
| **LOG-08** | Timestamps in metadata are those of INTAKE_PROTOCOL.md (arrival to the second). The server **MUST NOT** add finer-grained times, nor the respondent's local time, nor anything derivable from the client. |

## 8. Transport and deployment security

| Id | Requirement |
|---|---|
| **SEC-01** | **TLS only.** TLS 1.2 at the oldest, 1.3 preferred, modern suites only. No plaintext listener beyond a health check that answers nothing but liveness. HSTS with a long `max-age`. |
| **SEC-02** | Every response carries `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and a `Content-Security-Policy: default-src 'none'`. A `GET blob` is `application/octet-stream` with `Content-Disposition: attachment`; the server never serves a stored body as anything a browser would render. |
| **SEC-03** | **CORS** is configured as a list of origins. The respondent endpoints (INTAKE_PROTOCOL.md §4) answer the preflight for those origins and expose only `Retry-After`; **the organiser endpoints (§5) get no CORS headers at all**. An empty list means no cross-origin access, not "any". `Access-Control-Allow-Origin: *` is a configuration error the server refuses at start-up (`--check-config`). |
| **SEC-04** | The server **runs unprivileged**, with write access to its data directory only, with resource limits (memory, open files, processes) and, where the platform allows, a sandbox (a read-only root, no network beyond what it serves). A crash restarts it; a crash loop is visible. |
| **SEC-05** | **No secret has a default.** The operator allowlist (AUT-08) is a file; a signing or TLS key is the operator's own; the server refuses to start with an example value from its own documentation. |
| **SEC-06** | The server **refuses to start** on a configuration it cannot vouch for: an unreadable data directory, a public host that is not a valid host (INTAKE_PROTOCOL.md §2), a missing contact line or source URL, a wildcard CORS origin, a cap above the hard cap. `--check-config` reports **every** problem at once and exits non-zero. |
| **SEC-07** | Input is **parsed once, strictly, at the edge**: headers, ids, JSON bodies and cursors against their grammars; nothing reaches storage that did not pass. A request for an id is looked up by its validated text and **never** used to build a path from anything else. |
| **SEC-08** | The code that reads untrusted bytes is **fuzzed** (routes, headers, the signed-request header, the JSON bodies) and has a mutation-tested core; a regression test exists for every crash or hang ever found. |
| **SEC-09** | A **security contact** is published (`security.txt`, `operator_contact`), with a stated way to report and a stated response time; the reference server publishes a coordinated-disclosure policy. |

## 9. Operations

| Id | Requirement |
|---|---|
| **OPS-01** | **Configuration** is one file plus a few flags, documented in full: public host, data directory, operator allowlist, CORS origins, caps and windows (LIM), retention (STO-05), contact line, source URL, listen address. No setting is only in an environment variable. |
| **OPS-02** | **Health.** A liveness answer that reveals nothing; a readiness check for the store and the clock; neither lists forms, counts or sizes. |
| **OPS-03** | **Backup and restore** are documented and tested: what a consistent backup is while the server runs, how to restore, what a restored server does about submissions collected after the backup (the organiser's client sees the `sid` it already imported and treats the second as a duplicate — INTAKE_PROTOCOL.md §5.5). |
| **OPS-04** | **Upgrade and migration**: a new version reads the old store; a store is never rewritten in place without a backup being possible first; a downgrade is either supported or refused cleanly. |
| **OPS-05** | The documentation states **what a backup still holds after a purge** and for how long, so that the retention the respondent was promised is the retention the operator keeps. |
| **OPS-06** | **Decommissioning**: when the server ends (the end date of §10), the operator tells the organisers in good time, they collect what is left (the file route is the fallback, FORM_INTAKE.md §6.7), and the operator deletes the store and the backups. The procedure is written down before the server is run for anyone. |
| **OPS-07** | The server **MUST NOT** need a database administrator: one embedded store, no separate service. |
| **OPS-08** | Time is kept by the operating system's clock under NTP (AUT-03); the server logs a clock step. |

## 10. The operator and the maintainer

A server is a **second product**: it opens a public upload endpoint (FORM_INTAKE.md §14). **Phase 4 does not start
without a named maintainer**, and no server runs for anyone without the following.

| Id | Requirement |
|---|---|
| **ORG-01** | A **named maintainer** — a person or an organisation, with an address the world can write to. *Nobody is named at the time of writing (D3, decided when phase 3 is done).* |
| **ORG-02** | A **support promise** in words: what is supported, for which versions, how fast a security report is answered, how fast one is fixed. |
| **ORG-03** | An **end date, or a renewal date**, published with the server. A dropbox that has silently no maintainer any more is the worst failure this design has. |
| **ORG-04** | **No hosted service by the foundation.** The foundation publishes the code and the protocol; whoever runs a server is its operator, its processor-of-ciphertext and the party that signs a processing agreement with the organiser (art. 28 GDPR) where one is needed. |
| **ORG-05** | The operator administers the **allowlist** (AUT-05) as a decision about *who may create forms on this server*, and keeps a record of the decision. |
| **ORG-06** | **Incident handling** is written down: what the operator does when a key is suspected compromised, when the store is damaged, when abusive content is reported (the server cannot read it — the answer is *delete without reading* and tell the organiser), when a legal request arrives (what the operator holds is ciphertext and the metadata of STO-08). |

## 11. Supply chain and licensing

| Id | Requirement |
|---|---|
| **SUP-01** | The code is **EUPL-1.2**. EUPL treats giving access to a program's essential functionality over a network as communication, so a modified server **MUST** point at its source in `GET /v1/info` (`source_url`, PRO-08). |
| **SUP-02** | A **software bill of materials** ships with every release, and **every dependency is pinned** to an exact version; a dependency change is a reviewed change. |
| **SUP-03** | Releases are **signed** (the foundation's minisign key, as the app's) and reproducible where the platform allows; the checksum of a release is published with it. |
| **SUP-04** | The server depends on **`ocideck_form_core`** for everything the wire and the formats share (routes, bodies, signed requests, bundle verification), so that there is **one** implementation of the grammars. A second implementation in the server of anything the core already does is a defect. |
| **SUP-05** | The **protocol** is CC-BY-4.0 and the **vectors** CC0 (D5); the server's repository carries a copy of both, and its test suite runs the vectors. |
| **SUP-06** | Under the EU Cyber Resilience Act the server is open-source software that the foundation does not offer commercially; the maintainer **MUST** still keep a vulnerability-handling process (SEC-09) and **MUST** not claim a conformity the project has not assessed. |

## 12. How conformance is shown

A requirement nobody tests is an intention. The server ships — and the project maintains — the following.

| Id | Requirement |
|---|---|
| **TST-01** | **The shared vectors** (`intake_protocol_vectors.json`, CC0) pass, byte for byte: signed requests, invite links, token and secret hashes. |
| **TST-02** | A **conformance suite that is black-box**, runnable against any server's `/v1` with only a URL, an operator key and a test form — so a different implementation can be checked, not only the reference one. It exercises at least: the order of the upload checks (PRO-03); idempotent retry and `409` (PRO-04); the cap **to the byte** (LIM-01); a withdrawal with a right, a wrong and a repeated secret (PRO-10); a signed request at the edges of the window and a replay (AUT-01); an unauthorised organiser, and one who left the bundle (AUT-06); a publication with a lower, equal and unequal `bundle_seq` (PUB-03); a bundle for another host (PUB-02); the purge when every organiser has acknowledged it (STO-05); a restart in the middle of all of this (STO-01). |
| **TST-03** | A **web smoke test against a real running server**, with a web respondent: the CORS preflight, an upload, the `Retry-After` header being readable. The web build is otherwise unguarded by `flutter test`, where `kIsWeb` is always false. |
| **TST-04** | A **privacy test**: after a full run of TST-02, every log, metric and file the server wrote is searched for the tokens, secrets, bodies and full IP addresses the run used; a hit fails the build (LOG-01, LOG-02). |
| **TST-05** | A **hardening checklist** (SEC-01 … SEC-07, LOG-03, OPS-01 … OPS-03) with a command or an observation for each line, run before every release; **the checklist green is a condition of phase 4's gate** (FORM_INTAKE.md §12). |
| **TST-06** | A **load and abuse test** with a fixed shape: many slow clients, many tiny ones, an oversize declared length, a body longer than declared, a flood of one token, a flood from one bucket, a disk filled to the quota — and the property checked after each is that an honest upload, an organiser's list and an `ack` still succeed. |
| **TST-07** | **Mutation testing** of the server's decision logic (the order of checks, the caps, the window, the purge rule), as for the core: a surviving mutant is a dead branch or a missing test. |
| **TST-08** | A **client↔server version matrix** once more than one protocol version exists (FORM_INTAKE.md §14). |

## 13. What is not required — and what is still open

**Not required, on purpose.** Content moderation (the server cannot read the content), virus scanning, thumbnails,
search, an administration interface, a web page of its own, e-mail or push notification, respondent accounts, per-form
statistics, billing. Each is either impossible for a blind store or would turn the dropbox into a backend. An operator
who wants one builds it *beside* the server, not into it.

**Open points found while writing these requirements** — each needs an owner's decision, or an additive member in the
protocol (a server may add a member to a response within version 1, and clients ignore it):

1. **The purge warning has no place on the wire.** FORM_INTAKE.md §6.5 says the organiser is warned 14 days before a
   purge, and LIM-06 says they are warned at 80 % of a cap. The protocol's listing carries neither. *Proposal:* an additive
   `purge_at` on each listed submission and, in the list response, a `warnings` array of `{code, …}`; the Inbox shows
   them. Until it is in the protocol, the server can only put them in its operator-facing output.
2. **Rate and cap defaults** (LIM-09) are guesses; they want a first real use (the Kookboek call) before they are
   promises.
3. **More than one instance** (AUT-04): a shared nonce store is a second moving part. *Proposal:* the reference server
   is a single instance by design — one process, one directory — and says so; a deployment that needs more writes its
   own shared cache and is on its own.
4. **Single-use tokens** are deferred (FORM_INTAKE.md D6). When they come, STO-08 gains a token-use record, and LOG-05
   needs re-checking.
5. **Tombstones keep a hash for 24 months** (STO-06), which sits awkwardly beside "metadata goes with the ciphertext".
   The reason is idempotent withdrawal; a lawyer should say whether 24 months is the right length for it.
6. **The operator's allowlist** (AUT-05, AUT-08) is administration by a file. For a server with many forms a small,
   audited CLI would be kinder than hand-editing; it must still not be reachable over the network.
7. **A hosted deployment by a third party** (ORG-04) is a processor relationship the foundation will be asked about; a
   template processing agreement would help organisers and is out of this document's reach.

## 14. Where this fits

| Document | What it holds |
|---|---|
| [`FORM_INTAKE.md`](FORM_INTAKE.md) §2.1, §6, §9, §14 | The design: the seven conditions, the shape of the server, the threats, the price and the preconditions of phase 4. |
| [`INTAKE_PROTOCOL.md`](INTAKE_PROTOCOL.md) | The contract on the wire. |
| This document | What the server must make true around the contract, and what its operator must promise. |
| `packages/ocideck_form_core` | The grammars, bodies, routes, signed requests and bundle verification the server shares with the client. |
