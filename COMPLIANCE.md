<!--
SPDX-License-Identifier: EUPL-1.2
Copyright © 2026 Stichting LibreKAT
-->

# Voluntary security attestation

> **What this is.** A self-assessment against the light-weight voluntary security
> attestation (VSA) checklist drafted by the [ORC WG](https://github.com/orcwg/cra-attestations)
> (`proposals/template-lite.md`, derived from BSI TR-03185-2), in the context of
> Article 25 of the Cyber Resilience Act.
>
> **What it is not.** Not a conformity claim, not a certification, and not an
> audit. Nobody checked this but us. The Cyber Resilience Act imposes no
> obligations on this project — see
> [`assurance/CRA-2024-2847-positie.md`](assurance/CRA-2024-2847-positie.md) —
> and issuing this attestation takes none on.
>
> **Why publish it anyway.** Because the alternative is that every downstream
> user asks the same questions by e-mail. Most of the answers already existed,
> scattered across a dozen files; this gathers them.
>
> **Status:** revised · 2026-09-01 · reflects the default branch on that date.
> First issued 2026-07-22; revised 2026-09-01 (#1889) to reflect that the
> project now has releases, a CI runner, and per-PR secret/SAST scanning.

**Two boxes below are not ticked.** That is the point of the document. A
checklist with a quiet yes in a row that deserves a no teaches the reader to
distrust the rows that are true.

---

## Authorship

**AU.01 — Issuing entity**

| | |
|---|---|
| Name | Stichting LibreKAT |
| Chamber of Commerce (KvK) | 98657836 |
| Address | Weidemolen 12, 2211 PW Noordwijkerhout, Netherlands |
| | Wilhelminaplein 12, 8911 BS Leeuwarden, Netherlands |
| Website | <https://librekat.nl> |
| General contact | stichting@librekat.nl · +31 85 333 2942 |

The KvK number is the unambiguous identifier: an address can be shared or
change, a registration number identifies the legal person. Both addresses are as
published by the foundation itself, on <https://librekat.nl/nl/contact/> and in
the app under **Settings → About OciDeck**.

The foundation publishes OciDeck and holds the copyright. It does not sell it
and does not monetise it in any form. Nobody buys it, nobody subscribes, and
there is no paid edition.

It runs **two** servers, and both belong in this paragraph rather than only in a
table further away:

- `cveapi.librekat.nl`, a CVE mirror the application can talk to — off by
  default and repointable at any other mirror. No deck ever reaches it.
- `ocideck.librekat.nl`, a public build of the web app, free to use and
  advertised in the README. Everything still runs in the visitor's browser and
  no deck is uploaded, but the origin is the foundation's: it sees the requests
  for the bundle, and it carries the same-origin fetch-proxy, so a URL a visitor
  imports there is fetched by the foundation's server.

Both are processing operations by the foundation, with the foundation as
controller. [`docs/PRIVACY.md`](docs/PRIVACY.md#the-servers-the-publisher-runs)
says per server what the application sends and what this repository can
establish — and for the CVE mirror, since the operator stated it (2026-07-23),
that the foundation keeps what the service receives only as long as it needs to
run it (art. 5(1)(e), no fixed schedule) and judges the privacy impact minor. No
such statement has been made for the demo host yet, and none is invented here.

*(Corrected 2026-07-22, #579: "does not host it as a service" read as "runs no
servers at all", and that was the sentence a critical reader would check first.
Corrected again 2026-07-23, #589: the replacement said the foundation does not
host OciDeck as a service and runs exactly one server, while the demo at
`ocideck.librekat.nl` was already live. Hosting a free public copy is still
hosting; the correction that fixed one absolute claim had left a second one
standing.)*

On the CRA's own vocabulary: the foundation is **not a manufacturer**, because
the software is not made available on the market. Whether it is an *open-source
software steward* under Article 3(14) is genuinely open — the reasoning, and why
it cannot be closed today, is in
[`assurance/CRA-2024-2847-positie.md`](assurance/CRA-2024-2847-positie.md). This
attestation therefore describes the relationship rather than claiming the label.

**AU.02 — Contact**

| | |
|---|---|
| Primary contact | Brenno de Winter |
| Role | Initiator and sole active maintainer (see [`AUTHORS.md`](AUTHORS.md)) |
| Security contact | security@librekat.nl |

**AU.03 — Scope**

| | |
|---|---|
| Project | OciDeck |
| URL | <https://pawprint.vigilis.online/LibreKAT/Ocideck> |
| Valid for versions | **The default branch and the `v*` release tags.** 23 tags exist, latest `v0.4.9` (23-08-2026) |
| Valid for dates | Issued 2026-07-22; revised 2026-09-01; describes the branch as of that date |

`pubspec.yaml` carries `0.4.10+24`. Releases are tagged `v*` and built by an
automated pipeline (`.forgejo/workflows/release.yml`) with minisign-signed
artefacts. See [`SECURITY.md`](SECURITY.md), *Supported versions*.

---

## Governance

- [x] **GV.01 — Contribution guideline.** [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [x] **GV.02 — The guideline sets a quality standard.** It does, and the
      standard is executable rather than aspirational: `make check` must be green,
      and it gates analysis with `--fatal-infos`, the full test suite,
      conventions, method length, file and class size, dead code, the privacy
      projection boundary, and two coverage floors. See
      [`docs/CHECKS.md`](docs/CHECKS.md).
- [x] **GV.03 — Usage and intended purpose documented.**
      [`README.md`](README.md) and [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)

## Licensing

- [x] **LE.01 — All components under an open source licence.**
      [`LICENSE.md`](LICENSE.md) — EUPL-1.2.
- [x] **LE.02 — Dependencies under open source licences.**
      [`docs/LICENSE_COMPLIANCE.md`](docs/LICENSE_COMPLIANCE.md), enforced by
      `make licenses`, which fails on a non-open-source dependency.

## Quality

- [x] **QA.01 — Direct dependencies listed, with checksums.**
      [`sbom/`](sbom/) carries CycloneDX 1.6 and SPDX 2.3 for *all* components,
      not only direct ones; `pubspec.lock` carries the pinned versions.
      `make sbom-verify` fails when the committed SBOM has drifted.
- [x] **QA.02 — Source and change history public.** The forge, linked above.
      Every change lands through a pull request.
- [x] **QA.03 — How to file a vulnerability report.**
      [`SECURITY.md`](SECURITY.md)
- [x] **QA.04 — Repeatable test procedures.**
      [`docs/CHECKS.md`](docs/CHECKS.md) and the [`Makefile`](Makefile). They run
      locally and on the forge: `static-gate` and `scans` per PR (`static-gate`
      also on every push to `main`), `linux-gate` nightly on the tip of `main`,
      and `ci.yml` on tag pushes (see QA.06 for the contributor gap).
- [x] **QA.05 — Memory-safety mitigations.** One dependency is not memory-safe:
      `opencv_core` → `dartcv` (C++), which decodes untrusted image data. The
      mitigations, and — measured, not assumed — exactly which malformed inputs
      do and do not reach the decoder, are in
      [`docs/SECURITY_DESIGN.md` §6.1](docs/SECURITY_DESIGN.md). Regression tests
      in `test/image_face_scan_test.dart`.
      **Ticked with a stated limit:** there is no fuzzing corpus, and a crash
      inside the native library takes the process down.
- [ ] **QA.06 — More than one active contributor.** **No.** One. The bus factor
      is one, and it is the largest single risk in this project — larger than
      anything a scanner has reported. See
      [`CONTRIBUTING.md`](CONTRIBUTING.md), *Who reviews this, and who does not*.
- [ ] **QA.07 — Every change reviewed by a human non-author.** **No**, for the
      maintainer's own changes, which are self-merged. The requirement is
      conditional on QA.06 and so does not formally bite — but leaving it blank
      would be evasive.
      Worth stating in both directions: a pull request *you* send is reviewed by
      a non-author. The gap runs one way.

## Build and release

- [x] **BR.01 — How to build from source.** [`docs/BUILD.md`](docs/BUILD.md)
- [x] **BR.02 — Unique, monotonically increasing version identifiers.**
      Releases are tagged `v*` (semver), 23 tags exist, latest `v0.4.9`.
      `pubspec.yaml` carries `0.4.10+24`. The release pipeline builds and
      publishes artefacts per tag.
- [x] **BR.03 — Integrity of released assets, and how to verify it.**
      Each release carries `SHA256SUMS` and a minisign signature
      (`SHA256SUMS.minisig`). The macOS build is signed with a Developer ID and
      notarised. Linux and Windows are (yet) unsigned. See
      [`docs/BUILD.md`](docs/BUILD.md) for verification instructions.
- [x] **BR.04 — A descriptive log of functional and security changes per
      release.** [`CHANGELOG.md`](CHANGELOG.md) is kept per change, in the
      user's language, and a security fix is marked `Security:`. Each release
      tag has a release body on the forge.

## Vulnerability management

- [x] **VM.01 — A security contact.** **security@librekat.nl**. Private
      reporting and what happens to a report are in
      [`SECURITY.md`](SECURITY.md).
      Internally the project holds itself to terms — first response 5 working
      days, an assessment within 10, a fix within 90 calendar days — and
      `tool/check_service_norms.dart` measures them against the tracker rather
      than leaving them as an intention. They are stated here as *what we
      measure*, not as a service level offered to a reporter: `SECURITY.md`
      deliberately promises an acknowledgement "as quickly as we reasonably can",
      and this document is not the place to quietly upgrade that into a
      commitment.
- [x] **VM.02 — Publish information about discovered vulnerabilities.**
      [`CHANGELOG.md`](CHANGELOG.md) and the public tracker, with a `Security:`
      marker on entries that close a vulnerability. There is no formal advisory
      format; none has been needed, and inventing one before the first case would
      be guessing at its shape.

## End-of-life

- [x] **EL.01 — Discontinuation of support communicated, with a policy.**
      [`SECURITY.md`](SECURITY.md), *End of life and what "supported" means*.
      In short: the default branch is what is supported; discontinuation is
      announced in `README.md`, `SECURITY.md` and `CHANGELOG.md` with at least
      three months' notice; vulnerability reports stop being answered after that
      and the file will say so; and the source is archived rather than deleted so
      anyone may fork.

---

## Subscribing to security notifications

The ORC WG's light-weight summary asks for this, and it is not a template row:

- **Releases feed** —
  `https://pawprint.vigilis.online/LibreKAT/Ocideck/releases.rss`

There are 23 releases in the feed, latest `v0.4.9`. A security fix is marked
`Security:` in the release notes and [`CHANGELOG.md`](CHANGELOG.md). There is
deliberately no mailing list — a subscriber list is personal data we would have
to hold and protect, and a feed is not. [`SECURITY.md`](SECURITY.md) lists the
alternatives and what they carry.

## Where the risk assessment lives

The Cyber Resilience Act's Annex I Part I asks for a documented risk assessment,
and it is a different artefact from a threat model. Ours is
[`assurance/risicoafweging.md`](assurance/risicoafweging.md): ten risks, their
consequence and likelihood, and — the part that matters — the five that are
deliberately **accepted**, each with what would put the decision back on the
table.

The largest risk in it is not technical. It is R9: one maintainer.

## Machine-readable

The same facts in a form a tool can read, without anyone having to ask us:
[`security-insights.yml`](security-insights.yml) (OpenSSF Security Insights
v2.2.0). It is guarded against drifting from `SECURITY.md` — see
`test/security_insights_test.dart`.

## Where this is weakest

Read this section first if you are deciding whether to depend on the project.

1. **One maintainer, self-merge** (QA.06/QA.07). Everything else on this page
   rests on one person continuing to care. There IS a CI runner since
   23-07-2026 (per-PR scans, post-merge gate, tag-push gate), but it does not
   replace a second reviewer.
2. **One non-memory-safe dependency on the image path** (QA.05), mitigated and
   documented, not fuzzed.
3. **Linux and Windows artefacts are unsigned** (BR.03). The macOS build is
   signed and notarised; the other two are not, so verification on those
   platforms is limited to the minisign-signed `SHA256SUMS`.

None of the three is hidden anywhere else in this repository either. They are
collected here because a reader deserves them in one place rather than assembled
from a dozen files.
