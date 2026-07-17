# OciDeck Documentation

OciDeck is a privacy-first Marp presentation builder for desktop and web, with no
application backend — everything runs locally. This folder holds the project
documentation. Start here and jump to what you need.

> **Status:** pre-release (currently 0.2.0). There is no formal versioning or
> release scheme yet.

## For users

| Document | What it covers |
|---|---|
| [USER_GUIDE.md](USER_GUIDE.md) | Full user manual — every feature, workflow, and slide type. |
| [SHORTCUTS.md](SHORTCUTS.md) | Keyboard shortcuts. |
| [FAQ.md](FAQ.md) | Common questions about features, security, and privacy. |
| [PRIVACY.md](PRIVACY.md) | What data stays local, what leaves only on your action, and how. |
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
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | Migration format template (no numbered releases exist yet). |

## For operators & compliance

| Document | What it covers |
|---|---|
| [HOSTING.md](HOSTING.md) | Serving the web build safely (static host, CSP headers, fetch-proxy). |
| [SECURITY_DESIGN.md](SECURITY_DESIGN.md) | Security principles and the concrete mechanisms that enforce them. |
| [LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) | Dependency licence compliance. |
| [SBOM.md](SBOM.md) | The Software Bill of Materials (EU CRA). |
| [GLOSSARY.md](GLOSSARY.md) | OciDeck-specific terms in one place. |

## Design notes (`design/`)

Design proposals and rationale — historical/forward-looking, **not** current-state
references (where they disagree with the code, the code wins):
[COLLABORATION](design/COLLABORATION.md) ·
[GIT_STORAGE](design/GIT_STORAGE.md) ·
[PENTEST_MIAUW](design/PENTEST_MIAUW.md) ·
[AI_ASSIST](design/AI_ASSIST.md) ·
[OCIWACHT](design/OCIWACHT.md) ·
[AGENTIC_BUILD_PLAN](design/AGENTIC_BUILD_PLAN.md) ·
[PROCESS_IMPROVEMENT](design/PROCESS_IMPROVEMENT.md).

## New here?

- **I want to use OciDeck** → [USER_GUIDE.md](USER_GUIDE.md), then [FAQ.md](FAQ.md).
- **I want to build/hack on it** → [DEVELOPMENT_SETUP_GUIDE.md](DEVELOPMENT_SETUP_GUIDE.md), then [ARCHITECTURE.md](ARCHITECTURE.md).
- **I want to host the web build** → [HOSTING.md](HOSTING.md).
- **I need to assess its security/privacy** → [SECURITY_DESIGN.md](SECURITY_DESIGN.md) and [PRIVACY.md](PRIVACY.md).
- **I hit a term I don't know** → [GLOSSARY.md](GLOSSARY.md).

## Licence

OciDeck is released under the **EUPL-1.2**. Contributions are accepted under the
same licence.
