# OciDeck — Software Bill of Materials (SBOM)

> **Status:** current-state description of a generated artefact · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

OciDeck ships a machine-readable **Software Bill of Materials**: a complete,
version-pinned inventory of every third-party component in the product. It is
generated from the files that are already the source of truth, checked into the
repository, kept current by a staleness gate in the test suite (enforced by every
`make check`), and shipped with the web build and with release artefacts —
see *Where it ships* below.

Two industry-standard formats are produced from one generator:

| File | Format | Spec |
| --- | --- | --- |
| [`sbom/ocideck.cdx.json`](../sbom/ocideck.cdx.json) | **CycloneDX** | 1.6 (JSON) |
| [`sbom/ocideck.spdx.json`](../sbom/ocideck.spdx.json) | **SPDX** | 2.3 (JSON) |
| [`sbom/ocideck.sbom.md`](../sbom/ocideck.sbom.md) | **Markdown** | human-readable view |

The Markdown file is a scan-friendly rendering of the same inventory — a licence
summary plus a grouped table of every component with its version, licence and
supplier — for anyone browsing the repository. The two JSON files are authoritative and
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

That paragraph describes an obligation on *manufacturers*. Stichting LibreKAT is
not one: OciDeck is an open-source project, made freely available and not offered
as a service, so the Regulation's obligations do not attach. We build the SBOM
anyway, because an inventory of what you ship is part of building software
properly — and because a reader deserves to be able to check. The reasoning is
recorded in `assurance/CRA-2024-2847-positie.md`.

## What it covers

The inventory is derived from the files that pin the build — `pubspec.lock`,
`assets/web_export/MANIFEST.json` and `.tool-versions` (see
[`tool/sbom_build.dart`](../tool/sbom_build.dart)). That makes it exact about
what the repository *declares*. One gap is worth naming: the build-SDK row is
read from `.tool-versions`, and nothing checks that the Flutter actually
resolved on the building machine matches it. Build with a different toolchain
and the SBOM will not notice. *(Corrected 2026-07-22: this said the inventory
"can never disagree with what is actually built", which is falsifiable on any
machine whose Flutter differs from the pin.)*

| Group | Source of truth | Per-component data |
| --- | --- | --- |
| **Dart/Flutter packages** (direct + transitive) | `pubspec.lock` + each package's own `pubspec.yaml` | version, `pkg:pub` purl, archive SHA-256, hosted URL, dependency scope, licence, supplier, **its own dependencies** |
| **Vendored JS/CSS export bundles** | `assets/web_export/MANIFEST.json` | version, `pkg:npm` purl, SHA-256, source URL, licence |

Each vendored bundle is an **unmodified upstream build**, and you do not have to
take that on trust: the `source` field in `MANIFEST.json` is the URL it came
from, so

```sh
curl -sL "<source>" | shasum -a 256
```

must print the `sha256` recorded beside it. `make deps-check`
(`tool/check_bundled_js.dart`) compares the files on disk against that same
manifest — which is a within-repository check, so it catches a file changed
without its hash, not a hash and file changed together. The command above is the
one that reaches outside. *(Added 2026-07-22: this property held but was written
down nowhere, and "why should I believe you did not touch 3.5 MB of minified
mermaid" is the first question a reviewer asks.)*
| **Vendored plugin forks** | `pubspec.lock` (`third_party/`) | version, upstream VCS URL **pinned to the exact commit**, upstream revision, SHA-256 **tree hash** of the vendored directory, licence, supplier |
| **Bundled fonts** | `pubspec.yaml` (`flutter.fonts`) + the OFL texts in `assets/fonts/` | file SHA-256, licence (OFL-1.1), supplier |
| **Build SDKs** | `.tool-versions`, `pubspec.yaml` | Flutter version, Dart SDK constraint, supplier |

### The dependency graph

The document carries the **whole** graph, not just the application's own row:
every package declares the dependencies *it* pulls in, read from its own
`pubspec.yaml` in the resolved package root and narrowed to the versions pub
actually resolved. That is one CycloneDX `dependencies` entry per component and
the matching SPDX `DEPENDS_ON` relations.

> Until 2026-07-22 the graph was one layer deep: a single entry for the root, 46
> edges over 200 components, and **153 components in no relation at all**.
> `pubspec.lock` is a flat list — it says what is in the build, not who pulled it
> in — so a graph built from it alone cannot answer the question that gets asked
> the morning a CVE lands on a transitive parser: *what reaches this, and can I
> drop it?* It is now 661 edges and nothing is unreferenced;
> `test/sbom_test.dart` fails if a component appears in no relation.

A component whose own manifest we cannot read gets **no `dependencies` entry at
all** rather than an empty one. CycloneDX reads an absent entry as "unknown" and
an empty `dependsOn` as "checked, none" — writing the second where we mean the
first would be the same silent over-claim as a one-layer graph, only quieter.

### Supplier (NTIA minimum element)

Each component names the entity that supplies it, **derived and never invented**:

- a package's declared `repository:` (else `homepage:`) on a forge yields the
  account it is published under — `https://github.com/dart-lang/tools` →
  `dart-lang`; any other URL yields its host — `https://flutter.dev` →
  `flutter.dev`;
- a package with `source: sdk` is supplied by the SDK it ships inside, which is
  what `pubspec.lock` states about it (`flutter_test`, `sky_engine`, … →
  `flutter`);
- a vendored fork takes its upstream project's account;
- a bundled font takes the copyright holder its OFL text names, plus that text's
  own project URL;
- OciDeck itself is `Stichting LibreKAT`.

A **registry or CDN URL yields nothing**: `cdn.jsdelivr.net` delivers DOMPurify,
it does not supply it, and naming it would be worse than an empty field. That is
the one remaining gap — the six vendored JS/CSS bundles carry no supplier,
because the only URL we hold for them locally is the CDN they were fetched from.
Everything else (194 of 200 components) names one. There is no table of "who
really maintains what" in the generator; such a table ages badly and reads as a
fact once it is in an SBOM.

SPDX carries the name (`Organization: dart-lang`); CycloneDX carries the name
**and** the URL it was derived from, so the derivation is checkable. Whether a
forge account belongs to a company or to one person is not determinable offline,
so all of them are emitted as `Organization:`.

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

## Proving the bundled JavaScript is unmodified

*Added 2026-07-22.* The offline HTML export inlines about 5.8 MB of third-party
JavaScript, and the first question a reviewer asks about that is fair: **why
should I believe you have not touched 3.5 MB of minified mermaid?**

`make deps-check` alone does not answer it. It compares each file against the
`sha256` in `assets/web_export/MANIFEST.json`, and both live in this repository —
whoever changes one changes the other. That check catches an accident or a
half-finished upgrade, not a deliberate edit.

What does answer it is the `source` URL the manifest records per bundle:

```
dart run tool/check_bundled_js.dart --verify-upstream
```

That refetches every bundle from its upstream URL and compares hashes. As of
2026-07-22 all six are **byte-identical to upstream** — marked, highlight.js,
DOMPurify, mermaid, MathJax and the highlight.js stylesheet.

To check one by hand, without trusting this tool either:

```bash
curl -sL https://cdn.jsdelivr.net/npm/marked@18.0.5/lib/marked.umd.js | shasum -a 256
```

and compare against the `sha256` for that entry in `MANIFEST.json`.

It is **opt-in rather than part of `make deps-check`**, deliberately: it pulls
~6 MB from a CDN, and the daily gate should not fail because someone else's CDN
is down. Run it when you upgrade a bundle, before a release, or whenever you
want the answer for yourself.

## Where it ships

- **Web build** — `make build-web` copies all three files into
  `build/web/sbom/`, so a deployed instance serves them from `/sbom/` on the
  same origin.
- **Desktop bundles** — the `.app`, `.exe` and Linux bundle do **not** carry the
  SBOM inside them. `make build-macos`, `build-windows` and `build-linux` do run
  the freshness gate (`sbom-verify`) first, so a stale inventory cannot be built
  against, but the files themselves travel in the release artefact rather than
  in the bundle.
- **Releases** — `.github/workflows/release.yml` uploads them as the
  `ocideck-sbom` artifact and the web bundle carries its copy. That workflow has
  never run: there is no CI runner (see [CHECKS.md](CHECKS.md)).
- **Desktop builds do not carry it *inside* the bundle.** `make build-macos`,
  `build-windows` and `build-linux` have no copy step, so hand `sbom/` over
  alongside the binary until the release process exists (#520). They do now run
  `sbom-verify` first, so at least a desktop bundle cannot be built against a
  stale inventory. *(Amended 2026-07-22: that prerequisite was added in the same
  pass; before it, a hand-made desktop bundle could ship against a stale SBOM.)*

*(Corrected 2026-07-22: the summary at the top of this document said "shipped
with every build", which was true only of the web build — and README calls
OciDeck a desktop application, so the three targets that do not carry it are the
primary product.)*

## CRA mapping

| CRA requirement (Annex I, Part II) | Where OciDeck satisfies it |
| --- | --- |
| §1 — SBOM in a commonly used, machine-readable format, covering ≥ top-level deps | `sbom/ocideck.cdx.json` (CycloneDX 1.6) + `sbom/ocideck.spdx.json` (SPDX 2.3), covering **all** components **and the relations between them** — see above |
| §1 — identify and document components | Generated from `pubspec.lock` / `MANIFEST.json` / `pubspec.yaml`; completeness, graph reachability and supplier presence enforced by `test/sbom_test.dart` |
| §2 — address and remediate vulnerabilities without delay | `make deps-check` queries [OSV](https://osv.dev) for the vendored JS bundles; the CycloneDX SBOM feeds external scanners (Dependency-Track / osv-scanner) for the Dart/Flutter graph |
| Keeping the documentation up to date | `make sbom-verify` staleness gate in the test suite (`make check`); reproducible resolution via the committed `pubspec.lock` (`--enforce-lockfile` is declared in the CI workflow, which is not currently running) |

## See also

- [`LICENSE_COMPLIANCE.md`](LICENSE_COMPLIANCE.md) — the open-source licence policy and gate.
- [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) — human-readable component notices.
- [`../SECURITY.md`](../SECURITY.md) — vulnerability reporting and supply-chain hardening.
- [`CHECKS.md`](CHECKS.md) — every automated check, including `make sbom-verify`.
