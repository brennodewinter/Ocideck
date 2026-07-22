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
> **Status:** first issue · 2026-07-22 · reflects the default branch on that date.

**Three boxes below are not ticked.** That is the point of the document. A
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

The foundation publishes OciDeck and holds the copyright. It does not sell it,
does not host OciDeck itself as a service, and does not monetise it in any form.

It does run **one** service the application can talk to: `cveapi.librekat.nl`, a
CVE mirror, off by default and repointable at any other mirror. That is not
hosting OciDeck — no deck ever reaches it — but it is a processing operation by
the foundation, with the foundation as controller, and it belongs in this
paragraph rather than only in a table further away.
[`docs/PRIVACY.md`](docs/PRIVACY.md#the-one-server-the-publisher-runs) says what
the application sends, what this repository can establish, and — since the
operator stated it (2026-07-23) — that the foundation keeps what the service
receives only as long as it needs to run it (art. 5(1)(e), no fixed schedule)
and judges the privacy impact minor. *(Corrected 2026-07-22, #579: "does not
host it as a service" read as "runs no servers at all", and that was the
sentence a critical reader would check first.)*

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
| Valid for versions | **The default branch.** There are no releases and no version tags |
| Valid for dates | Issued 2026-07-22; describes the branch as of that date |

There is no version identifier to attest to. `pubspec.yaml` carries `0.1.0+1`,
but that changes only when someone bumps it, so many different commits show the
same number. **The commit hash is the only real identifier** — pin it and record
it. See [`SECURITY.md`](SECURITY.md), *Supported versions*.

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
      locally; there is no CI runner (see QA.06).
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
- [ ] **BR.02 — Unique, monotonically increasing version identifiers.** **No
      releases exist**, so there is nothing to version. Tracked in
      [issue #520](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/520).
- [ ] **BR.03 — Integrity of released assets, and how to verify it.** **No
      released assets exist.** Users build from source, so the integrity
      guarantee available today is the commit history itself. Also #520.
- [ ] **BR.04 — A descriptive log of functional and security changes per
      release.** No releases — but the log exists:
      [`CHANGELOG.md`](CHANGELOG.md) is kept per change, in the user's language,
      and a security fix is marked `Security:`. This row becomes a yes the day
      BR.02 does.

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

It is **empty today**, because there are no releases. That is precisely why it is
the one to subscribe to: the day it carries an item, that item is a release, and
a security fix will be in its notes. There is deliberately no mailing list — a
subscriber list is personal data we would have to hold and protect, and a feed is
not. [`SECURITY.md`](SECURITY.md) lists the alternatives and what they carry.

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

1. **One maintainer, self-merge, no CI runner** (QA.06/QA.07). Everything else on
   this page rests on one person continuing to care.
2. **No releases, so no signed or verifiable artefacts** (BR.02–04). You build
   from source and pin a commit; there is no update mechanism and the project
   cannot tell you that you are behind.
3. **One non-memory-safe dependency on the image path** (QA.05), mitigated and
   documented, not fuzzed.

None of the three is hidden anywhere else in this repository either. They are
collected here because a reader deserves them in one place rather than assembled
from a dozen files.
