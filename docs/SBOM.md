# OciDeck — Software Bill of Materials (SBOM)

> **Status:** current-state description of a generated artefact · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

OciDeck ships a machine-readable **Software Bill of Materials**: a complete,
version-pinned inventory of every third-party component in the product. It is
generated from the files that are already the source of truth, checked into the
repository, kept current by a staleness gate in the test suite (enforced by every
`make check`), and shipped with every build.

Two industry-standard formats are produced from one generator:

| File | Format | Spec |
| --- | --- | --- |
| [`sbom/ocideck.cdx.json`](../sbom/ocideck.cdx.json) | **CycloneDX** | 1.6 (JSON) |
| [`sbom/ocideck.spdx.json`](../sbom/ocideck.spdx.json) | **SPDX** | 2.3 (JSON) |
| [`sbom/ocideck.sbom.md`](../sbom/ocideck.sbom.md) | **Markdown** | human-readable view |

The Markdown file is a scan-friendly rendering of the same inventory — a licence
summary plus a grouped table of every component with its version and licence —
for anyone browsing the repository. The two JSON files are authoritative and
carry the SHA-256 hashes and purls; all three are generated together and kept in
sync by the same gate.

Both are consumable by common tooling — CycloneDX works out of the box with
[Dependency-Track](https://dependencytrack.org/), `osv-scanner`, `grype`, and
`trivy`; SPDX is the ISO/IEC 5962:2021 standard favoured by licence-compliance
tooling.

## Why (Cyber Resilience Act)

The **EU Cyber Resilience Act** (Regulation (EU) 2024/2847), **Annex I,
Part II, §1** requires manufacturers of products with digital elements to:

> "identify and document vulnerabilities and components contained in products
> with digital elements, including by drawing up a **software bill of materials
> in a commonly used and machine-readable format** covering at the very least
> the top-level dependencies of the products".

OciDeck goes beyond the "top-level" minimum and lists **all** components, direct
**and** transitive. See [the CRA mapping](#cra-mapping) below.

## What it covers

The inventory is assembled from files under version control, so it can never
disagree with what is actually built (see [`tool/sbom_build.dart`](../tool/sbom_build.dart)):

| Group | Source of truth | Per-component data |
| --- | --- | --- |
| **Dart/Flutter packages** (direct + transitive) | `pubspec.lock` | version, `pkg:pub` purl, archive SHA-256, hosted URL, dependency scope, licence |
| **Vendored JS/CSS export bundles** | `assets/web_export/MANIFEST.json` | version, `pkg:npm` purl, SHA-256, source URL, licence |
| **Vendored plugin forks** | `pubspec.lock` (`third_party/`) | version, upstream VCS URL **pinned to the exact commit**, upstream revision, SHA-256 **tree hash** of the vendored directory, licence |
| **Bundled fonts** | `pubspec.yaml` (`flutter.fonts`) | file SHA-256, licence (OFL-1.1) |
| **Build SDKs** | `.tool-versions`, `pubspec.yaml` | Flutter version, Dart SDK constraint |

Licences are classified with the exact same logic as the compliance gate
(`tool/license_detect.dart`, shared with `tool/check_licenses.dart`), so the
SBOM and [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) always agree.

> That sentence was not true for the two vendored forks until 2026-07-22: their
> licence was **hardcoded** in the generator, and it was wrong —
> `desktop_multi_window` was listed as MIT while the file on disk is the
> Apache-2.0 text. Nothing is hardcoded now; both forks are classified from their
> own `LICENSE`, like every other component.

A path dependency has no pub archive, so the two forks had **no hash and no
upstream revision** — the only components in the document a verifier could not
check against anything. They now carry the upstream commit they were branched
from and a **tree hash**: SHA-256 over the sorted `<relative path> <sha256>` line
of every file in the vendored directory (dot-files excluded so it is
machine-independent). `make sbom-verify` recomputes it, so an edit inside
`third_party/` that is not committed with a fresh SBOM fails the gate.

## How to (re)generate

The SBOM is **derived, not hand-maintained**. Regenerate it whenever
dependencies change (add/upgrade a package, re-pin a JS bundle, bump the Flutter
version):

```sh
flutter pub get        # ensure the resolved graph + licences are on disk
make sbom              # writes the .cdx.json, .spdx.json and .sbom.md files
git add sbom/          # commit the regenerated files
```

## How it stays current

`make sbom` is deterministic: the component list is stably sorted and the
document identifier is derived from a content hash. The only non-deterministic
field is the creation timestamp.

`make sbom-verify` regenerates the SBOM in memory, normalises out the timestamp
and serial number, and fails if the result differs from the committed files.
This runs:

- inside the test suite ([`test/sbom_test.dart`](../test/sbom_test.dart), which
  also asserts completeness — every `pubspec.lock` package and every manifest
  bundle appears — and format validity), so it is enforced by every `make check`;
- as part of `make check-full`;
- and is declared in the CI workflow (`.github/workflows/ci.yml`), which does not
  currently run — the remote is Forgejo with no runner (see
  [CHECKS.md](CHECKS.md#continuous-integration)).

So a dependency change that forgets to refresh the SBOM fails `make check`.

## Where it ships

The SBOM travels with the product, not just the repository:

- **Web build** — `make build-web` copies all three files into
  `build/web/sbom/`, so a deployed instance serves them from `/sbom/` on the
  same origin.
- **Releases** — `.github/workflows/release.yml` uploads them as the
  `ocideck-sbom` artifact and the web bundle carries its copy.

## CRA mapping

| CRA requirement (Annex I, Part II) | Where OciDeck satisfies it |
| --- | --- |
| §1 — SBOM in a commonly used, machine-readable format, covering ≥ top-level deps | `sbom/ocideck.cdx.json` (CycloneDX 1.6) + `sbom/ocideck.spdx.json` (SPDX 2.3), covering **all** components — see above |
| §1 — identify and document components | Generated from `pubspec.lock` / `MANIFEST.json` / `pubspec.yaml`; completeness enforced by `test/sbom_test.dart` |
| §2 — address and remediate vulnerabilities without delay | `make deps-check` queries [OSV](https://osv.dev) for the vendored JS bundles; the CycloneDX SBOM feeds external scanners (Dependency-Track / osv-scanner) for the Dart/Flutter graph |
| Keeping the documentation up to date | `make sbom-verify` staleness gate in the test suite (`make check`); reproducible resolution via the committed `pubspec.lock` (`--enforce-lockfile` is declared in the CI workflow, which is not currently running) |

## See also

- [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) — the open-source licence policy and gate.
- [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) — human-readable component notices.
- [`../SECURITY.md`](../SECURITY.md) — vulnerability reporting and supply-chain hardening.
- [`CHECKS.md`](CHECKS.md) — every automated check, including `make sbom-verify`.
