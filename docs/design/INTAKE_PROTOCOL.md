# OciDeck — Intake protocol, version 1

> **Status:** the contract of phase 4 of [`FORM_INTAKE.md`](FORM_INTAKE.md) (§6, §12) — **specified; the server is not built yet** · **Status last reviewed:** 2026-10-03 · **Published by:** Stichting LibreKAT
>
> **Licence:** this document is **CC-BY-4.0**; the test vectors in
> `packages/ocideck_form_core/test/fixtures/intake_protocol_vectors.json` are **CC0** (D5). The code
> that implements it stays EUPL-1.2. A third party may write a compatible server or client from this
> document alone, without a copyleft question.
>
> **What exists today.** The pure half of the contract is in `packages/ocideck_form_core` and tested
> (the first part also against the vectors): the invite link, the information document, the arrival
> note, the withdrawal secret, the invite token, the error codes, **signed organiser requests**, the
> **bodies** of every operation, and the **routes** — which method and path mean which operation, read
> by one grammar for the client and the server (§§2–6). What is not built is the reference server, the
> client transport and the web respondent; each paragraph says which it is. The server needs a **named
> maintainer** before it is run for anyone (FORM_INTAKE.md §14, D3), and the web respondent needs a way
> to seal in a browser (§5.6 there).

---

## 1. What this protocol is for, and what it refuses to be

A respondent fills in a form and the **encrypted** submission travels to a **dropbox** that cannot
read it. The organisers — the people who made the form — fetch it later and open it on their own
machines. The server stores ciphertext and a little metadata, and is trusted with **nothing but
availability**: it can withhold, delay or delete a submission, and it can say what it likes about
who sent one. It cannot read one, and it cannot make a respondent believe a form that does not come
from the person they were told it comes from (§3, FORM_INTAKE.md §5.1, §5.7).

It is **not** a backend. It never sees an answer and never validates one; a server that wants to
read plaintext is a different product (FORM_INTAKE.md §6.8). It has **no accounts, no sessions and
no cookies**: a respondent holds an invite token, an organiser signs each request.

## 2. Conventions

- **Transport.** HTTPS only. A client never follows a redirect to another host. The paths below are
  fixed by this document; the host is the one the invite link names (§3).
- **Request targets.** A target is `path[?query]` exactly as it is sent, and as a signed request signs
  it (§5.1). It is read **strictly**: letters, digits and `. _ ~ - / ? = &` only — no `%`, no `#`, no
  blank, nothing beyond ASCII, no absolute address, no trailing slash, no empty segment, and a query only
  where a route takes one (§5.5). There is one spelling of every request, so a cache, a proxy and a
  signature cannot disagree about it. A request is decided in this order, stopping at the first failure:
  the path has the shape of a route (`not-found`) → the route answers the method, upper case as received
  (`method-not-allowed`) → its ids are ids (`bad-request`) → its query is the route's (`bad-request`).
  *Built:* `matchIntakeRoute`, and the targets a client builds (`intakeFormTarget` and its siblings).
- **Versioning.** Every path starts with `/v1/`. A client that meets a server whose
  `protocol` (§4.1) is outside the versions it speaks stops, and says so.
- **Bodies.** JSON is UTF-8, `Content-Type: application/json; charset=utf-8`, **at most 64 KiB**
  except where a section gives another bound. The ciphertext of an upload and a download is
  `application/octet-stream`. **Every response carries `Cache-Control: no-store`.**
- **Unknown members.** A client **ignores** a member of a *server's response* it does not know, so
  that a server can add one without raising the protocol version. A server **refuses** a member of a
  *request* it does not know (`bad-request`). The signed bundle is the one thing a respondent believes
  from a server, and it keeps its own strict rules (FORM_INTAKE.md §5.1): an unknown member there is
  refused.
- **Identifiers.** `fid` (a form), `sid` (a submission), an invite token and a request nonce are
  **26 characters of `[a-z2-7]`** — 128 random bits in lower-case base32 without padding, no time
  component. A key id (`kid`) has the same shape and is derived (FORM_INTAKE.md §5.1). An id outside
  the grammar is `bad-request`; **a directory or file name is made from a validated id, never from
  anything else**.
- **Binary values** are lower-case base32 without padding (RFC 4648), canonical: nothing but
  `[a-z2-7]`, a length a byte string can have, leftover bits zero. An Ed25519 public key is 52
  characters, a signature 103, a withdrawal secret 52. **Hashes are lower-case hex.**
- **Times.** An arrival time is UTC to the second, `2026-10-04T09:30:12Z`. A signed request carries
  Unix seconds (§5.1). Dates in a bundle are whole days (FORM_INTAKE.md §5.3).
- **Hosts.** `host[:port]`, lower-case letters, digits, dots and hyphens (the grammar of a bundle's
  `policy.api_host`). The host a client calls, the host in the invite link and the bundle's
  `policy.api_host` are **the same string**, and so is the host a request is signed for.

## 3. The invite link

```text
https://<shell host>/f/<fid>#api=<api host>&fp=<fingerprint>&t=<token>
```

The organiser shares it in any channel. It opens the **web form shell** the organiser hosts, which is
also the landing page a telephone opens. The **fragment is never sent to a server**.

| Part | Meaning |
|---|---|
| `<shell host>`, optional path prefix | Where the shell is hosted (never the intake server, never the foundation's demo — FORM_INTAKE.md §6.6). |
| `/f/<fid>` | The form. The path ends in `/f/` and an id; a trailing slash is fine. |
| `api` | The host of the intake server. Host names have no case: a client lower-cases it. |
| `fp` | The **fingerprint of the owner's signing key**, 52 characters (written however: in groups, upper case). It is the one thing a respondent has that the server does not control. |
| `t` | The invite token. |

**Reading it, in this order**, stopping at the first failure: it is an `https` address with a host and
no user name → its path ends in `/f/<id>` and the id is well formed → `api` is present and is a host →
**`fp` is present** and is a fingerprint → `t` is present and is a token. A parameter that appears
twice is refused; a parameter this version does not know is ignored.

**A link without `fp` is not complete and goes no further**: "This link is not complete. Ask the
organiser for the full invitation link." An earlier design let such a link continue with a prompt that
showed an organiser name taken from the very bundle being verified; a layperson cannot answer that, and
a hostile template would always arrive on that path. **A fingerprint that does not match the bundle's
signing key stops hard**, with no continue button.

*Built:* `parseInviteLink`, `InviteLink.text`, `newInviteToken`, `inviteTokenHash`.

## 4. Respondent operations

### 4.1 `GET /v1/info`

Anyone. The first request a client makes to a server.

```json
{
  "protocol": 1,
  "limits": { "max_package_bytes": 62914560 },
  "source_url": "https://example.org/ocideck-intake",
  "operator_contact": "beheer@example.org"
}
```

- `protocol` — the version this server speaks. A client that speaks versions *a* to *b* stops if it is
  below *a* ("this server is too old") or above *b* ("update the app").
- `limits.max_package_bytes` — the most bytes of one sealed package the server takes. A client uses the
  **lower** of this and its own hard cap (FORM_INTAKE.md §5.4); a server may lower a cap and never raise
  it past the client's.
- `source_url` — an `https` address where the server's source is: the offer EUPL-1.2 asks of a modified
  program run as a network service (FORM_INTAKE.md §6.5).
- `operator_contact` — a line, at most 200 characters, no control characters.

*Built:* `parseIntakeInfo`.

### 4.2 `GET /v1/forms/{fid}`

Anyone who knows the `fid`. The published form, in every language it is published in:

```json
{
  "state": "open",
  "variants": [
    { "bundle": { "v": 1, "fid": "…", "…": "the signed bundle, FORM_INTAKE.md §5.1" },
      "template": "the template text, as signed" }
  ]
}
```

- **One variant per template.** A bundle binds the SHA-256 of **one text**, and each language is its
  own text, so a form published in two languages has two variants. They share the `fid` and the
  `bundle_seq` counts on across them (FORM_INTAKE.md §7.1, as amended). A form has between 1 and 32
  variants. *(This replaces the single `{bundle, template, assets}` of the first design: nothing in a
  form references a file in v1, so there are no assets, and a second language needs a second bundle.)*
- `state` — `open` or `closed`. **Advisory**: it is not signed and the server enforces it. A respondent
  is told early that the form is closed; a server that lies about it gains nothing, because the upload
  is refused (§4.3) or accepted by what the server holds, not by what the client believed.
- The client **verifies every variant exactly as FORM_INTAKE.md §5.1 says** — signature against the
  fingerprint **from the invite link**, the template against `template_sha256`, `policy.api_host`
  against the host it called, `bundle_seq` against its pin — and offers those that pass. A variant that
  fails is dropped; if none passes the form is refused, with the reason of the first. The template's own
  `lang` (FORM_INTAKE.md §4.3) tells the client which variant is whose.
- The body is at most 8 MiB; a template at most 1 MiB; a bundle at most 256 KiB.

*Built:* `parseIntakeFormResponse` (lenient: unknown members ignored, `state` required) and the limits
`kIntakeMaxVariants`, `kIntakeMaxTemplateBytes`, `kIntakeMaxFormBytes`.

### 4.3 `PUT /v1/submissions/{sid}`

The respondent uploads the sealed package. The body is the **`age` ciphertext, streamed**.

| Header | Value |
|---|---|
| `Intake-Form` | the `fid` |
| `Intake-Token` | the invite token |
| `Intake-Withdrawal` | the lower-case hex SHA-256 of the **withdrawal secret's text** (§4.4) |
| `Content-Length` | required: a streamed upload says its size before the first byte |
| `Content-Type` | `application/octet-stream` |

**What the server does, in this order.** Each step ends the request with the error named.

1. `sid`, `Intake-Form`, `Intake-Withdrawal` outside their grammar → `bad-request`.
2. No `Content-Length` → `length-required`. More than the form's `max_package_bytes` (or the server's
   own cap, whichever is lower) → `too-large` **before a byte is read**.
3. No such form → `form-unknown`.
4. The SHA-256 of `Intake-Token` is not the form's current token hash → `invite-invalid`.
5. The form is closed — set closed by the owner, or past its `closes` day — → `form-closed`.
6. Over a rate limit (per network bucket and per token) → `rate-limited` with `Retry-After`.
7. Read the body **streaming, cutting it at the cap**: more bytes than declared or than the cap →
   `too-large`. Compute the SHA-256 while reading. **No decompression, no parsing, no scanning of
   ciphertext.**
8. Decide by what is stored under `sid`:
   - nothing → store it → **`201`** and the arrival note;
   - the same ciphertext hash, **same form** → **`200`** and **the same note** (an idempotent retry:
     the first response may have been lost);
   - another hash, or the same `sid` under another form → **`409` `submission-conflict`**; **never
     overwritten**.

The response body is the **arrival note**:

```json
{ "sid": "…", "at": "2026-10-04T09:30:12Z",
  "ciphertext_sha256": "…hex…", "contact": "redactie@example.org" }
```

It is **an arrival note, not proof against the server**: the server holds its own key and would sign
anything, so it is not signed. The respondent sees the hash and can quote it (FORM_INTAKE.md §5.8). The
client compares `ciphertext_sha256` with the hash of what it sent; a different one is an error.

*Built:* `IntakeArrivalNote`, `parseIntakeArrivalNote`, `newWithdrawalSecret`, `withdrawalSecretHash`.
The upload itself — the headers and the streaming — belongs to the transport and the server.

### 4.4 `POST /v1/submissions/{sid}/withdraw`

```json
{ "secret": "<52 characters>" }
```

The client made the secret (`newWithdrawalSecret`) and sent only its hash with the upload; it keeps
the secret in the copy the respondent saves. The server hashes what it is given and compares it with
the stored hash **without an early exit**.

- A match deletes the ciphertext **if it is still there**, records a **tombstone** `{sid, at, hash}` and
  answers `200 {"sid": "…", "at": "…", "deleted": true}`. `deleted` is `false` when the ciphertext was
  already gone; a **repeat** of the same withdrawal answers `200` with the first tombstone's `at`
  (idempotent). The tombstone holds the hash so that a lost response can be retried; it is kept 24 months.
- No such submission, **or a secret that does not match**, is the same `404` `submission-unknown`: the
  answer is not an oracle for which `sid`s exist. After the organisers have collected a submission and
  the server purged it (§5.5) there is nothing left to match; the client then tells the respondent to
  write to the contact line of the arrival note.
- A withdrawal is accepted **after the form's closing date** too (art. 7(3) GDPR); the organiser's
  listing then shows it, and the Inbox says "possibly already in print" rather than refusing.

A withdrawal is a *signal to the controller*, not a deletion the server can guarantee (FORM_INTAKE.md
§5.8, §9.3).

*Built:* `IntakeWithdrawRequest`, `IntakeWithdrawResult`.

## 5. Organiser operations

### 5.1 Signed requests

An organiser request carries **one header** and no secret:

```text
Authorization: OciIntake key=<sign>, ts=<seconds>, nonce=<nonce>, sig=<sig>
```

- `key` — the organiser's Ed25519 public key (the `sign` of their entry in the bundle), 52 characters.
- `ts` — the Unix time in whole seconds, written plainly (no sign, no leading zero, at most 12 digits).
- `nonce` — a fresh id.
- `sig` — the Ed25519 signature, 103 characters, over the UTF-8 bytes of the **canonical JSON**
  (RFC 8785, the subset of FORM_INTAKE.md §5.1) of

  ```text
  ["ocideck-intake-req-v1", host, method, target, body_sha256, ts, nonce]
  ```

  where `host` is the host the request goes to, `method` the upper-case HTTP method, `target` the
  request target **as sent, query included** (a paging cursor cannot be changed in flight), and
  `body_sha256` the hex SHA-256 of the body bytes — of nothing, `e3b0c442…b855`, for a request without
  one. **There is no other prefix**: the tag is the first element, which keeps these signatures apart
  from the bundle's (`ocideck-intake-bundle-v1\n`) and from the collaboration design's.

The header's four members may come in any order, with or without blanks after the commas; each appears
once; nothing else is in it.

**What a server does, in this order — the order is part of the contract.**

1. **Authenticate.** The header is well formed; `ts` is within **five minutes** of the server's clock,
   either way (`request-expired`); the signature holds for `key` over what *the server* knows the request
   to be — **its own public host**, the method and target it received, the hash of the body it read — never
   what the header claims (`signature-invalid`; an ill-formed header is also `signature-invalid`).
2. **Authorise.** The key may do this (§5.2): else `not-allowed`.
3. **Remember the nonce.** Only now, for `(key, nonce)`: one seen inside the window is a replay
   (`request-replayed`). A nonce is recorded **after** the first two steps so that a stranger signing with
   their own key cannot fill the cache. A server that holds as many nonces as it can answers
   `rate-limited` rather than forget one that still counts. A restart forgets them: what it lets through
   is a replay inside five minutes, which every operation below either tolerates (it is idempotent) or
   refuses a second time by what it does.

*Built:* `signIntakeRequest`, `verifyIntakeRequest`, `IntakeNonceCache`, `intakeRequestPreimage`.

### 5.2 Who may do what

| Operation | Who |
|---|---|
| `PUT /v1/forms/{fid}` — a **new** `fid` | a key on the **operator's allowlist** of organiser keys, and it must be the bundle's owner (§5.3). Without the allowlist the server is an anonymous 120 MiB-per-request storage service and a squatting target. |
| `PUT /v1/forms/{fid}` — an existing `fid` | the form's **owner key** only |
| `PUT /v1/forms/{fid}/token` | the owner key |
| list, `blob`, `ack`, `DELETE` | any organiser listed in the form's **current bundle** (the highest `bundle_seq`), by their `sign` key |

The **owner** is the organiser whose `sign` key hashes to the fingerprint of the key that first
published the form. A server knows an organiser's `kid` — which `ack` records — from the bundle entry of
the key that signed the request.

### 5.3 `PUT /v1/forms/{fid}` — publish

The owner publishes **the whole set** of variants, atomically:

```json
{ "state": "open", "variants": [ { "bundle": { … }, "template": "…" } ] }
```

`state` is optional (`open` when absent). The body is at most 8 MiB.

The server **verifies each bundle itself** — it holds the owner's fingerprint, the hash of the key that
signed the request, so it can run the whole of FORM_INTAKE.md §5.1 against the template that came with it —
and refuses the publication, naming `bundle-invalid` (not a bundle, bad signature, template mismatch), if
any does not. Further:

- every bundle's `fid` is the path's, and its `policy.api_host` is **this server's public host**
  (`bundle-host-mismatch`);
- the signer of the bundles is the key that signed the request;
- no variant's `bundle_seq` is **lower than the highest the server holds** for the form
  (`bundle-rollback`, `409`): equal is accepted, so that a re-publication is idempotent;
- the set replaces the previous one. Removing an organiser is a new bundle with a higher `bundle_seq`.

Answers `200 {"fid": "…", "variants": 2, "bundle_seq": 5}`.

*Built:* `parseIntakePublication` (strict: `state` optional, an unknown member **refused**, in the body and
in a variant), `IntakePublishResult`. *Not built:* the server's verification of each bundle.

### 5.4 `PUT /v1/forms/{fid}/token`

```json
{ "token_sha256": "<64 hex>" }      // rotate
{ "token_sha256": null }            // revoke: no one can upload until a new one is set
```

The organiser's client makes the token (`newInviteToken`), puts it in the invite links and sends only
its **hash**: the server never holds a token, it cannot leak one, and rotating it ends a link that spread
into a forwarded group chat. A form has **one** open token at a time in v1; single-use tokens are deferred
(FORM_INTAKE.md D6). Answers `200 {"token_set": true}` (`false` after a revoke).

*Built:* `IntakeTokenRequest` (the member must be present — `null` is an answer, a missing member is not),
`IntakeTokenResult`.

### 5.5 Listing, fetching, acknowledging, deleting

`GET /v1/forms/{fid}/submissions?after=<cursor>&limit=<n>` — a page, oldest first by `(at, sid)`:

```json
{ "items": [
    { "sid": "…", "at": "2026-10-04T09:30:12Z", "bytes": 1840221,
      "ciphertext_sha256": "…", "acked_by": ["<kid>"] },
    { "sid": "…", "at": "2026-10-05T18:02:44Z", "withdrawn": true }
  ],
  "next": "<cursor>" }
```

A tombstone has `withdrawn: true` and the time of the withdrawal. `next` is `null` on the last page;
a cursor is opaque, `[A-Za-z0-9_-]{1,64}`; `limit` is 1–100, 50 by default.

`GET /v1/submissions/{sid}/blob` — the sealed package, `application/octet-stream`, with
`Content-Length`. The organiser's client records `sid → ciphertext_sha256` at its first fetch and flags a
different hash later as *replaced* (FORM_INTAKE.md §5.6).

`POST /v1/submissions/{sid}/ack` — empty body; "landed safely", **per `kid`**. Idempotent. Answers
`200 {"acked_by": ["<kid>", …], "purged": false}`. **The purge rule:** the ciphertext is deleted when
**every organiser in the current bundle has acknowledged it** (`purged: true`), or — the hard cap —
**90 days after the form closes**; the organiser is warned 14 days before. Metadata goes with the
ciphertext; the tombstones are the only survivors. After a purge a repeat of the same upload would be
stored as new: the organiser's client sees the `sid` it already imported and treats the second as a
duplicate.

`DELETE /v1/submissions/{sid}` — removes the server's copy **without fetching it** (spam). `204`; a
repeat is `404`. It records no tombstone: it is not a withdrawal.

*Built:* `IntakeSubmissionPage` and `IntakeListedSubmission` (one bad line spoils the whole page: a list that
is silently shorter than the server's is worse than an error), `IntakeAckResult`, `isValidIntakeCursor`,
`intakeSubmissionsTarget`.

## 6. Errors

An error is an HTTP status and a body:

```json
{ "error": { "code": "form-closed", "message": "The form closed on 1 November; contact the organiser." } }
```

The `code` is the machine's; the `message` is the server's sentence, in its own language, for a person
who reads a log. **A client shows its own sentence for the code**, in the respondent's language, and keeps
the server's as detail.

| Code | Status | Meaning |
|---|---|---|
| `bad-request` | 400 | a header, an id, a target or a body outside its grammar |
| `length-required` | 411 | no `Content-Length` on an upload |
| `invite-invalid` | 401 | the invite token is missing, unknown or revoked |
| `signature-invalid` | 401 | the signature of an organiser request does not hold, or the header is ill formed |
| `request-expired` | 401 | `ts` is outside the window |
| `request-replayed` | 401 | this `(key, nonce)` was seen |
| `not-allowed` | 403 | the signature holds and the key may not do this |
| `form-closed` | 403 | the form is closed for uploads |
| `not-found` | 404 | no such path: nothing in this protocol answers there |
| `form-unknown` | 404 | no such form |
| `submission-unknown` | 404 | no such submission, or one already collected; also a wrong withdrawal secret |
| `method-not-allowed` | 405 | the path exists and does not answer this method |
| `submission-conflict` | 409 | another body under a `sid` that holds one |
| `bundle-rollback` | 409 | a `bundle_seq` below the one the server holds |
| `bundle-invalid` | 422 | a bundle that does not verify, or one for another form |
| `bundle-host-mismatch` | 422 | `policy.api_host` is not this server |
| `too-large` | 413 | more bytes than the cap |
| `rate-limited` | 429 | too many requests; `Retry-After` says when |
| `server-error` | 500 | the server failed |
| `unavailable` | 503 | the server cannot take it now |

A response whose body is not ours — a proxy's page, a code from a newer server — still gives an error:
the first code with that status (`404` is `not-found`, `502` is `server-error`, an unnamed `4xx` `bad-request`), with the body's
sentence if it has one.

*Built:* `IntakeErrorCode`, `IntakeError`, `parseIntakeError`.

## 7. Cross-origin use

The web form shell is served from the organiser's own host, so the respondent's requests (§4) are
cross-origin. The server answers the preflight and allows the origins its operator configures, the request
headers `Content-Type`, `Intake-Form`, `Intake-Token` and `Intake-Withdrawal`, the methods `GET`, `PUT`
and `POST`, and exposes `Retry-After`. **The organiser operations (§5) get no CORS headers at all**: an
organiser uses the desktop app, and a page in a browser has no business holding the signing key. A CORS
refusal is a clear error in the client — "use the desktop app, or the file route" — never a detour through
someone else's server.

## 8. What the server keeps, and for how long

The minimum bar is in FORM_INTAKE.md §6.5; the protocol-visible part is: ciphertext until every
organiser has acknowledged it or 90 days after the form closes; metadata with it; tombstones 24 months;
invite tokens and withdrawal secrets **only as hashes**; no full IP address beyond a short-lived truncated
one for rate limiting; and **the bundle, which is plaintext on the server** — the template, the
organisers' public keys and the policy (FORM_INTAKE.md §6.2). A form whose *existence* is sensitive
must not use a guessable `fid`.

## 9. Compatibility

Within version 1 a server may add members to its responses and a client ignores them (§2); it may not
change a path, a status, a code's meaning or a grammar. Anything else raises `protocol`, and a server may
answer both versions side by side. The error codes of §6 are a closed set per version: a code a client
does not know is read by its status.

## 10. Known limits

- **The sender is not authenticated.** The organisers' public keys are public, so anyone — a compromised
  server included — can seal a package for any `sid` (FORM_INTAKE.md §5.7). The maker check is the
  control, not this protocol.
- **A server can withhold, delay and delete.** Nothing here prevents it; the file route exists for the
  day that matters (FORM_INTAKE.md §6.7).
- **A replay after a purge is stored as new** (§5.5); the organiser's client detects the duplicate `sid`.
- **A restart of the server forgets its nonces** (§5.1).
- **The five-minute window needs clocks.** A client whose clock is further out than that cannot make an
  organiser request (`request-expired`); comparing its clock with the server's `Date` header is how it can tell the organiser why.

## 11. Test vectors

`packages/ocideck_form_core/test/fixtures/intake_protocol_vectors.json` (CC0): a signing seed, the key and
fingerprint it makes, two signed requests with their preimage, body hash and header (one with a query and
no body, one with a body), the hashes of an invite token and a withdrawal secret, and invite links that
read and that are refused. The signatures were also verified independently with Node's OpenSSL Ed25519
when the file was made. An implementation is compatible when it reproduces every value in it.
