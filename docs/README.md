# OciDeck Documentation

OciDeck is a privacy-first Marp presentation builder for desktop and web, with no
application backend — everything runs locally. This folder holds the project
documentation. Start here and jump to what you need.

> **Status:** unreleased. No release has ever been tagged. `pubspec.yaml` says
> `0.2.0+1`, but that string is not a version anyone can act on: no tag carries
> it, the app never shows it, and every user runs whatever commit they built
> from. See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) and
> [`../SECURITY.md`](../SECURITY.md) under *Supported versions*.
>
> *(Corrected 2026-07-22: this line read "pre-release (currently 0.2.0)", which
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
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | What the app migrates by itself (settings), and the rules for adding the next one. No releases are tagged yet. |

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
read that banner first. All nine ship with the app.

| Document | What it is |
|---|---|
| [COLLABORATION.md](design/COLLABORATION.md) | Design proposal, unbuilt: real-time collaboration, presenting and calls. |
| [GIT_STORAGE.md](design/GIT_STORAGE.md) | Design of the git storage plane; phases 0–6 have landed, what remains is verification. |
| [PENTEST_MIAUW.md](design/PENTEST_MIAUW.md) | The original design for the MIAUW pentest module, which ships. Parts are contradicted by the code. |
| [AI_ASSIST.md](design/AI_ASSIST.md) | The optional AI assistance design; phases 0–3 are built, phase 4 (MCP) is not. |
| [OCIWACHT.md](design/OCIWACHT.md) | The privacy scanner design, with a per-section delivered/open table at the top. |
| [AGENTIC_BUILD_PLAN.md](design/AGENTIC_BUILD_PLAN.md) | Historical: the agentic build plan for the pentest/AI work. Executed; kept as a worked example, not a queue. |
| [PROCESS_IMPROVEMENT.md](design/PROCESS_IMPROVEMENT.md) | Design proposal, unbuilt: a Lean Six Sigma authoring module. Despite the name it is a product design, not a report about our process. |
| [VERIFICATION.md](design/VERIFICATION.md) | A worklist, in Dutch: what has been built and passes its own tests but has never met a real server, a second operating system or a real report. |
| [LEXICON_LICENTIENAVRAAG.md](design/LEXICON_LICENTIENAVRAAG.md) | A licensing dossier, in Dutch: three lexicon sources that would enrich the privacy check, and why none of them can be bundled yet. |

*(Corrected 2026-07-22: this list named seven of the nine documents in
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

## Licence

OciDeck is released under the **EUPL-1.2**. Contributions are accepted under the
same licence.
