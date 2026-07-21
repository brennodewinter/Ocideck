# OciDeck — Glossary

OciDeck-specific terms and the acronyms that recur in the codebase and docs. For
where things live in `lib/`, see [SOURCE_MAP.md](SOURCE_MAP.md).

## Core concepts

**OciDeck** — a privacy-first Marp presentation builder for desktop and web, with
no application backend; all processing is local.

**Deck** — a complete presentation: metadata, an ordered list of slides, a theme
profile, and a TLP classification. Immutable model (`lib/models/deck.dart`).

**Slide** — one immutable, strongly-typed slide. Its `SlideType` (21 values)
selects the layout: `title`, `section`, `bullets`, `twoBullets`, `bulletsImage`,
`twoImages`, `image`, `video`, `quote`, `table`, `freeMarkdown`, `code`, `chart`,
`cockpit`, `question`, `timeline`, and the pentest layouts (`finding`,
`findingsSummary`, `checklist`, `scopeMatrix`, `signOff`).

**Marp** — the open Markdown-for-presentations format OciDeck reads and writes.
Decks stay close to plain Marp Markdown, so they interoperate with other Marp
tools. See [FILE_FORMAT.md](FILE_FORMAT.md).

**Theme profile** — colours, fonts, logo, and footer settings for a deck. Shared
as an `.ocideckstyle` file. Per-slide visual overrides live on the slide itself.

**Cockpit** — a dashboard-style slide type showing several metrics/KPIs at a
glance.

**Presenter mode** — the dual-screen presentation view: presenter notes, timer,
and controls on one screen; the full slide on the other (desktop).

## Files & storage

**`.ocideck`** — a single-file package (zip) bundling a deck and its assets; can
be password-encrypted.

**`.ocideckstyle`** — a shareable theme/style profile file.

**Forge** — a git hosting service OciDeck can talk to over REST (Gitea/Forgejo,
GitHub, GitLab). The git backend is "WebDAV with version history" — the same source shape
plus commits, tags, and a version chooser.

**Fetch-proxy** — a small optional server-side endpoint (`fetch-proxy?url=…`) the
**web** build uses to fetch URLs that browser CORS would otherwise block. It
applies the same SSRF rules as NetGuard. See [HOSTING.md](HOSTING.md).

## Privacy & classification

**OciWacht** — OciDeck's built-in privacy scanner. It detects personal data
(email, phone, IBAN, BSN and national IDs for 13 EU member states plus two UK
ones, addresses, names, secrets) and
can flag or redact it. Name detection is deliberately not NER (see
[design/OCIWACHT.md](design/OCIWACHT.md)).

**TLP (Traffic Light Protocol)** — the sharing-classification scheme: `CLEAR`,
`GREEN`, `AMBER`, `AMBER+STRICT`, `RED` (plus an unset `none`). OciDeck can
enforce a release ceiling on export.

**Disposition** — a per-slide privacy decision for a scanner finding
(`warn`, `accept`, `shield`, `redact`).

**Projection** — the transform that turns a source `Deck` into an
**AudienceDeck** for a specific audience, applying redaction. `forAudience`
respects per-slide dispositions; `forExternalProcessing` is stricter (redacts
everything found).

**AudienceDeck** — a deck that has been through a privacy projection. Its
constructor is private, so only the projection can produce one; export surfaces
must accept an `AudienceDeck`, never a raw `Deck` — a boundary enforced at
compile time.

**Redaction manifest** — the record of what was redacted from a sealed deck, so a
redacted export can be verified against its source without a false tamper alarm.
It is written as two files beside the export: `<name>-redactions.json`, which may
travel with the report, and `<name>-redaction-keys.json`, which holds the salts
and stays with the source — the separation between them is what keeps a
commitment from being reversible. See FILE_FORMAT.md §12.

**Document seal** — a SHA-512 hash over a deck's canonical content, stored in the
front matter, giving tamper-evidence for finalised documents.

## Security mechanisms

**NetGuard** — the SSRF guard (`lib/utils/net_guard.dart`): rejects internal/
private/metadata addresses, unwraps IPv4-in-IPv6, and resolves-then-pins to
defeat DNS rebinding.

**SecretStore** — OS-keychain storage for secrets (WebDAV password, S3 secret
access key, AI API key, git token) via `flutter_secure_storage`. The S3 access
key *ID* is not a secret here — it stays in the prefs domain with the endpoint
and bucket name.

**trustedInternal** — an explicit per-connection opt-in that lets a user-chosen
internal server bypass the private-range block (and use plain `http`). Never
applies to deck-supplied URLs.

**SBOM** — Software Bill of Materials (CycloneDX + SPDX), the dependency inventory
required by the EU CRA. See [SBOM.md](SBOM.md).

**CRA** — the EU **Cyber Resilience Act** (Reg. (EU) 2024/2847), which the SBOM
tooling targets.

## Pentest module (MIAUW)

**MIAUW** — *Methodiek voor Informatiebeveiligingsonderzoek met Auditwaarde*, the
Dutch methodology for audit-grade security testing. OciDeck's opt-in
"Informatieveiligheid" module supports authoring pentest reports to it. See
[design/PENTEST_MIAUW.md](design/PENTEST_MIAUW.md).

**Finding** — a security-issue slide group (header + detail + evidence) sharing
one finding id.

**Scope matrix / Sign-off** — pentest report layouts: the tested scope, and the
formal acceptance/sign-off page.

**CWE** — MITRE's *Common Weakness Enumeration*. OciDeck bundles the full CWE list
offline for the finding editor's picker.

**CVE** — *Common Vulnerabilities and Exposures*. OciDeck can build a local,
offline CVE database (desktop) and search it.

**CVSS** — *Common Vulnerability Scoring System* (v4), used to score findings.

**WSTG** — the OWASP *Web Security Testing Guide*, bundled as a reference catalog.

## Build & quality

**`make check`** — the required local gate: format, static analysis, conventions,
method-length, dead-code, and the test suite with the coverage floor. See
[CHECKS.md](CHECKS.md).

**Ratchet** — a downward-only baseline (e.g. max file length 1000, max method
length 150): existing over-limit spots are grandfathered but may only shrink, and
no new violations are allowed.

**Coverage floor** — the minimum enforced line coverage (currently **80 %**).
