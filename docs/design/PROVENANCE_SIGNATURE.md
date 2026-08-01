# OciDeck — Herkomstbewijs: cryptografische ondertekening van het verspreide deck (Design)

> **Status:** design proposal — unbuilt · **Status last reviewed:** 2026-08-01 · **Published by:** Stichting LibreKAT

> **A design proposal — not yet implemented.**
> This is the pick-up-cold implementation design for the **owner provenance
> signature** on a distributed deck — the third and last part of
> [`COLLABORATION.md`](COLLABORATION.md) Phase 2 (identity hardening & provenance,
> [issue #978]). It reuses the self-encrypted relay's device identity
> ([`SELF_ENCRYPTED_RELAY.md`](SELF_ENCRYPTED_RELAY.md) §4.3) and the existing seal
> sidecar ([`../FILE_FORMAT.md`](../FILE_FORMAT.md) §6.6). No new cryptographic
> primitive, no byte added to the `.md`.
>
> Reviewed 2026-08-01 by three role lenses (bewaker, security-architect, jurist):
> **akkoord-mits** — the conditions they set are folded into this document (§8).

[issue #978]: https://git.pawprint.dev/librekat/ocideck/issues/978

## 1. The gap it fills

The `.seal.json` sidecar already proves three things and not the fourth:

| Existing | Proves | Weakness |
| --- | --- | --- |
| `hash` (SHA-512 over `.md` bytes) | the content did not change | anyone can re-hash a modified file and re-seal |
| `timestamp_token` (RFC 3161) | it existed at time *T* | says nothing about *who* |
| `signature` (name/role/image) | a claim in text | not cryptographically bound |
| **➕ `provenance` (Ed25519)** | **this exact deck was signed by the holder of this identity key** | — |

The value materialises only together with **device verification** (COLLABORATION
Phase 2, "Blok A"): the fingerprint a recipient compared out-of-band is the same
key that signs the deck. Verify an identity once → trust every deck it signs. It
closes the loop that the bare hash (integrity) and RFC 3161 (time) leave open:
*authorship*.

## 2. Where it lives — one new key in the existing sidecar

No new file, no byte in the `.md`. A `provenance` block in `<name>.seal.json`
(it is opaque → it belongs beside the file, per the 0.1.0 format decision that
moved the seal out of the front matter, FILE_FORMAT §3.6/§6.6):

```json
"provenance": {
  "alg": "ed25519",
  "preimage": "ocideck-provenance-v1",
  "identity_key": "base64(Ed25519 public key, 32 bytes)",
  "signature": "base64(signature, 64 bytes)",
  "signed_at": "2026-08-01T12:00:00.000Z"
}
```

Added **without raising `SealCodec.version`** — the same deliberate choice as
`timestamp_nonce` (`lib/services/seal_codec.dart`): an older build reads per key
and ignores it, rather than rejecting the whole sidecar and losing the seal.

The `preimage` value in the JSON is the **exact** domain tag that is signed (§3) —
there is no second, shorter spelling. A third party reads it straight from the
file and reconstructs the signed bytes verbatim.

## 3. What is signed — the preimage

The Ed25519 signature is over a documented, reproducible byte string built with
the same structured-encoding pattern the rest of `collab_crypto.dart` uses for
its signed messages (a JSON array, not ad-hoc string concatenation — so a future
free-text field can never reopen a delimiter-injection gap):

```
utf8( jsonEncode([
  "ocideck-provenance-v1",   // domain tag == the block's "preimage" value
  form,                      // e.g. "file-bytes-v1"
  algo,                      // e.g. "sha-512"
  hash,                      // lowercase hex, the seal's SHA-512 over the .md bytes
  signedAt,                  // ISO-8601 UTC, == the block's "signed_at"
]) )
```

`form`/`algo`/`hash` are exactly the existing seal fields; `signedAt` is signed
too so the displayed signing date cannot be altered without breaking the
signature (RFC 3161 remains the authoritative *time* anchor when present). All
five are constrained values (a domain constant, an enum key, `sha-512`, hex, an
ISO timestamp), so no member can carry a delimiter that forges the array shape.

Third-party verification, no OciDeck:

```console
$ sha512sum rapport.md          # → hash
# rebuild the JSON array above, then Ed25519-verify(signature, identity_key)
```

A **test vector** pins the exact bytes, mirroring the seal's own test vector in
FILE_FORMAT §6.6, so the build fails if the preimage layout ever drifts.

## 4. The key = the collaboration device identity

Signing uses the existing Ed25519 identity (`CollabDeviceKeys`, seeded and
persisted via the keychain — `collab_device_store.dart`). The signing and
verifying helpers both live **inside** `collab_crypto.dart` (the single crypto
file); `document_integrity.dart` must not import `package:cryptography`, or the
"one file to review for all crypto" property is lost.

The helper is **provenance-scoped, never a raw-bytes oracle**: it takes the seal
fields and builds the domain-separated preimage internally
(`signProvenance(form, algo, hash, signedAt)` / `verifyProvenance(...)`), so the
identity key can never be made to sign caller-chosen bytes that would sidestep
the domain separation.

The identity seed is exportable (this is what "Blok B" / recovery builds on): a
signer can carry the same identity to another device, and — the honest-constraint
answer — signed decks stay verifiable with any standard Ed25519 tool even if
OciDeck disappears.

## 5. Triggers (owner's decision, 2026-08-01)

Signing is **opt-in, never silent**, offered in two places:

- **At the existing seal/finalize act** — also outside a collaboration session
  (e.g. a MIAUW pentest report), beside the human signature block.
- **At the distribution boundary** — session end (SELF_ENCRYPTED_RELAY §9 "End"):
  only the **authority/owner** is offered "sign this deck before you distribute
  it". Co-authors do not sign; the owner stands behind the final artifact.

It is **independent** of the human `signature` block: the provenance signature
does **not** cover the name/role/image fields; either can exist without the other.

## 6. Verification UX — no cryptic states, no legal overclaim

On open, when a `provenance` block is present, exactly one outcome, worded to
avoid any eIDAS "handtekening" suggestion (see §8, jurist):

- **Herkomst bevestigd** — signature valid *and* `identity_key` is pinned in the
  device trust store (Blok A) → *"Herkomst bevestigd — ondertekend met een eerder
  bevestigde sleutel."*
- **Herkomst-sleutel niet eerder bevestigd** — signature valid, key not pinned →
  *"Herkomst-sleutel niet eerder bevestigd — vingerafdruk `<…>`."* This is **not**
  an authorship claim; it invites out-of-band comparison.
- **Ongeldig**, split by cause (the two checks are independent):
  - hash mismatch → *"Herkomst klopt niet — bestand gewijzigd na ondertekening."*
  - hash ok, signature fails → *"Ondertekening ongeldig of vervalst."*

Degrades cleanly **without Blok A**: with no trust store it shows only the
fingerprint, never a "confirmed" badge. So this feature functions on its own; the
trust store only enriches it.

## 7. Threat model & non-goals

- **Positive signal only.** A stripped or replaced `provenance` block cannot be
  prevented in a beside-the-file model (and keeping it out of the `.md` is the
  right call). Provenance gives a *positive* signal — the "confirmed" badge for a
  pinned identity. A recipient who pinned the owner must read the **absence** of
  the badge as the signal: a stripped block shows an unsigned deck, a re-signed
  block shows "not previously confirmed". This is an explicit non-goal, documented
  for the user.
- **Self-signed anchor.** `identity_key` travels in the block, so `deviceFingerprint`
  is computed over the *supplied* key — an attacker can present any fingerprint.
  The only anchor is the out-of-band pinned identity (Blok A). The design never
  claims authorship for an unpinned key.
- **Key role broadening.** The identity key goes from *ephemeral session signing*
  to *durable authorship in distributed files*. A device-key compromise therefore
  forges past and future authorship too. Acceptable given the domain separation,
  but stated here rather than left implicit.
- **Not a legal signature.** A self-generated Ed25519 key with no third-party
  identity binding is neither an advanced nor a qualified electronic signature
  (eIDAS). Docs and UI must not imply "non-repudiation", "bewijskracht",
  "onweerlegbaar" or "rechtsgeldig" — mirror the seal's existing nuance
  ("tamper-evidence, not tamper-proof").

## 8. Review conditions folded in (bewaker · security-architect · jurist)

All three: **akkoord-mits**. What changed versus the first draft:

**Security (blocking):**
1. The signing helper is provenance-scoped (§4), not a raw-bytes oracle.
2. The sidecar decode parses `provenance` defensively per key: a corrupt block
   yields no badge and **never** throws in a way that drops the surrounding seal
   (`hash`/`timestamp_token`/human `signature`). `seal_codec.decode` currently
   catches every exception and discards the whole sidecar; the provenance path
   must not ride that failure.

**Security (minor):** structured-encoding preimage (§3); `signed_at` is signed;
error message split by cause (§6); key-role broadening in the threat model (§7).

**Bewaker:** one unambiguous preimage token (the JSON value *is* the signed tag,
§2/§3) + a test vector like §6.6; document seed exportability (§4).

**Jurist (wording — never "handtekening"/"geverifieerde eigenaar" in the UI):**
overarching term **"herkomstbewijs"** (provenance), the UX strings in §6, no
non-repudiation claim in docs (§7), and a USER_GUIDE note that the public key /
fingerprint is a persistent pseudonymous identifier that stays in git history
(hence key rotation + the organisation/pentest scenario), while it leaks nothing
about the subjects *inside* the deck — only about the signer. `package:cryptography`
(Apache-2.0) fits EUPL-1.2 and already ships → attribution in
`THIRD_PARTY_NOTICES.md`, no SBOM-gate impact.

## 9. Code touch points

- `lib/collab/collab_crypto.dart` — `signProvenance` / `verifyProvenance` helpers.
- `lib/services/seal_codec.dart` — `provenance` key, defensive per-key decode.
- `lib/models/seal_record.dart` — a field for the provenance block (independent of
  `DocumentSignature`).
- `lib/services/document_integrity.dart` — the provenance verify path beside the
  hash check (calling into `collab_crypto`, not importing `package:cryptography`).
- Device trust store (Blok A) — for the "confirmed" badge; optional, degrades.
- UI — the opt-in at seal/finalize and at session end; the open-time status.
- Docs — FILE_FORMAT §6.6 (the `provenance` row + a verify note), COLLABORATION
  §9/§10, USER_GUIDE, SOURCE_MAP, CHANGELOG, THIRD_PARTY_NOTICES.
