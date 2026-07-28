# OciDeck — Documentation

> **Status:** index of this folder, current · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

OciDeck is a privacy-first Marp presentation builder for desktop and web, with no
application backend — everything runs locally. This folder holds the project
documentation. Start here and jump to what you need.

> **Status:** alpha — releases are tagged (latest `0.1.1`, 2026-07-27). See
> [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) and
> [`../SECURITY.md`](../SECURITY.md) under *Supported versions*.
>
> *(Corrected 2026-07-28: this said "unreleased. No release has ever been
> tagged" — true until `0.1.0` on 2026-07-25, stale since.)*
>
> *(Corrected 2026-07-22: this line read "pre-release (currently 0.1.0)", which
> reads as a version claim and contradicted both documents named above.)*

## For users

| Document | What it covers |
|---|---|
| [USER_GUIDE.md](USER_GUIDE.md) | Full user manual — every feature, workflow, and slide type. |
| [SHORTCUTS.md](SHORTCUTS.md) | Keyboard shortcuts. |
| [FAQ.md](FAQ.md) | Common questions about features, security, and privacy. |
| [PRIVACY.md](PRIVACY.md) | What data stays local, what leaves only on your action, and how. |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | What is accessible, and — the longer half — what is not. |
| [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) | Fixes for common problems. |
| [FILE_FORMAT.md](FILE_FORMAT.md) | The on-disk Markdown/Marp format — the stable contract. |

## For contributors & developers

| Document | What it covers |
|---|---|
| [CONTRIBUTING_GUIDELINES.md](CONTRIBUTING_GUIDELINES.md) | How to contribute: workflow, code style, testing. |
| [DEVELOPMENT_SETUP_GUIDE.md](DEVELOPMENT_SETUP_GUIDE.md) | Setting up a dev environment per platform. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture and layering. |
| [SOURCE_MAP.md](SOURCE_MAP.md) | Where things live in `lib/`. |
| [API_DOCUMENTATION.md](API_DOCUMENTATION.md) | Key internal APIs, models, services, and providers. |
| [BUILD.md](BUILD.md) | Build targets and the version pin. |
| [CHECKS.md](CHECKS.md) | The quality gates (`make check`) and what each enforces. |
| [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) | Enforced limits, measured sizes, and optimisation tips. |
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | What the app migrates by itself (settings), and the rules for adding the next one. |

## For operators & compliance

| Document | What it covers |
|---|---|
| [HOSTING.md](HOSTING.md) | Serving the web build safely (static host, CSP headers, fetch-proxy). |
| [SECURITY_DESIGN.md](SECURITY_DESIGN.md) | Security principles and the concrete mechanisms that enforce them. |
| [LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) | Dependency licence compliance. |
| [SBOM.md](SBOM.md) | The Software Bill of Materials (EU CRA). |
| [GLOSSARY.md](GLOSSARY.md) | OciDeck-specific terms in one place. |

## Design notes (`design/`)

Design proposals, rationale and open work — historical or forward-looking, **not**
current-state references. Where one disagrees with the code, the code wins. Each
of these carries its own status banner saying how far it has been overtaken;
read that banner first. All eleven ship with the app.

| Document | What it is |
|---|---|
| [COLLABORATION.md](design/COLLABORATION.md) | Design proposal, unbuilt: real-time collaboration, presenting, calls and a provider-adapter register spanning major, smaller and self-hosted meeting systems. |
| [TEAMS_GUEST_CLIENT.md](design/TEAMS_GUEST_CLIENT.md) | Design proposal, unbuilt: join supported Teams work/school meetings through an OciDeck web/PWA guest client without a Microsoft account. |
| [GIT_STORAGE.md](design/GIT_STORAGE.md) | Design of the git storage plane; phases 0–6 have landed, what remains is verification. |
| [PENTEST_MIAUW.md](design/PENTEST_MIAUW.md) | The original design for the MIAUW pentest module, which ships. Parts are contradicted by the code. |
| [AI_ASSIST.md](design/AI_ASSIST.md) | The optional AI assistance design; phases 0–3 are built, phase 4 (MCP) is not. |
| [OCIWACHT.md](design/OCIWACHT.md) | The privacy scanner design, **in Dutch**, with a per-section delivered/open table at the top. At 2,668 lines it is the largest of the three Dutch documents. |
| [AGENTIC_BUILD_PLAN.md](design/AGENTIC_BUILD_PLAN.md) | Historical: the agentic build plan for the pentest/AI work. Executed; kept as a worked example, not a queue. |
| [PROCESS_IMPROVEMENT.md](design/PROCESS_IMPROVEMENT.md) | Design proposal, unbuilt: a Lean Six Sigma authoring module. Despite the name it is a product design, not a report about our process. |
| [VERIFICATION.md](design/VERIFICATION.md) | A worklist, in Dutch: what has been built and passes its own tests but has never met a real server, a second operating system or a real report. |
| [LEXICON_LICENTIENAVRAAG.md](design/LEXICON_LICENTIENAVRAAG.md) | A licensing dossier, in Dutch: three lexicon sources that would enrich the privacy check, and why none of them can be bundled yet. |
| [OPENKAT_DISTRIBUTIE.md](design/OPENKAT_DISTRIBUTIE.md) | Design proposal, unbuilt: encrypted report distribution to a recipient who has minimal friction — double-click and view. The distribution side of the OpenKAT integration. |

*(Corrected 2026-07-22: this list named seven of the then-nine documents in
`design/`; `VERIFICATION.md` and `LEXICON_LICENTIENAVRAAG.md` were missing while
both are bundled as assets in `pubspec.yaml` and readable in the app. No test
compares the two lists, so nothing caught it.)*

## New here?

- **I want to use OciDeck** → [USER_GUIDE.md](USER_GUIDE.md), then [FAQ.md](FAQ.md).
- **I want to build/hack on it** → [DEVELOPMENT_SETUP_GUIDE.md](DEVELOPMENT_SETUP_GUIDE.md), then [ARCHITECTURE.md](ARCHITECTURE.md).
- **I want to host the web build** → [HOSTING.md](HOSTING.md).
- **I need to assess its security/privacy** → [SECURITY_DESIGN.md](SECURITY_DESIGN.md) and [PRIVACY.md](PRIVACY.md).
- **I depend on assistive technology** → [ACCESSIBILITY.md](ACCESSIBILITY.md).
- **I hit a term I don't know** → [GLOSSARY.md](GLOSSARY.md).

## How these documents are maintained

*Added 2026-07-22.* These rules were all being followed somewhere and written
down nowhere, which is why only a minority of the files followed them. They are
here now so a new document can be got right the first time.

**The code wins.** Every document in this folder describes software that changes
faster than prose. Where a document and the code disagree, the code is right and
the document is a defect. A claim you cannot check against the code does not
belong in a document — the set of guides removed on 2026-07-19 was convincing,
readable and described nothing that existed, and that is the failure mode this
rule exists to prevent.

**The title.** One `# OciDeck — <Name>` heading, first line, nothing above it.

**The masthead.** Directly under the title, one blockquote line:

```
> **Status:** … · **Status last reviewed:** YYYY-MM-DD · **Published by:** Stichting LibreKAT
```

Read that date narrowly: it says when someone last decided what *kind* of
document this is and whether that description still holds — a design proposal, a
current-state description, a procedure, a report, an executed plan. It is
deliberately **not** a claim that every sentence was re-verified on that date. A
document that has been checked line by line says so in its own words, as
`design/PENTEST_MIAUW.md` and `design/AI_ASSIST.md` do for the parts of them that
have been.

The publisher is **Stichting LibreKAT**, which holds the copyright. There is a
security contact; it is in [`../SECURITY.md`](../SECURITY.md) and it is
deliberately not repeated in this folder — see *Examples* below.

**Corrections carry a date, in the text.** When you fix a claim that was wrong,
say so where it was wrong rather than only in the commit message:

```
*(Corrected 2026-07-22: this said X. It says Y because …)*
```

A reader who remembers the old wording needs to know it changed and why; a
reviewer needs to see that someone looked. Together these notes are this
folder's change history, so leave the old ones standing.

**Refer to symbols, not line numbers.** Cite `maxPackageBytes` or
`resolveSlideAssetPath`, never "line 412" — the name survives a refactor and the
number does not.

**A number needs a date or it needs to go.** Any count that grows with the
codebase — tests, source files, packages, catalogue entries — is a measurement.
Give it the day it was measured, as [CHECKS.md](CHECKS.md) and
[LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) do, or leave it out. An undated
number is one nobody can tell has gone stale.

**Registering a new document.** A new `docs/*.md` has to be known in three
places, or `test/docs_registration_test.dart` fails `make check`:

1. the asset list in `pubspec.yaml`;
2. a reader tile in `lib/widgets/dialogs/parts/settings_dialog_docs.dart`;
3. a title translated into **every** supported language.

That third one is real work, so think twice before adding a file: in most cases
the material belongs in a document that already exists. A `NAME.<lang>.md`
translation of an existing document is the exception — it is picked up
automatically and must *not* get its own asset line or tile.

**Examples must be unmistakably invented.** These documents ship inside the app,
and the privacy scanner reads the whole folder as one document. A single
real-looking value — a national identity number, an IBAN, a working e-mail
address, a plausible phone number — escalates every special-category finding in
that file, including in text that has been there for years. Use values that are
obviously fictional, and keep working contact addresses in the root documents,
which are not bundled.

## Licence

OciDeck is released under the **EUPL-1.2**. Contributions are accepted under the
same licence.
