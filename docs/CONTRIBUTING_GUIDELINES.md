# OciDeck — Contributing Guidelines

> **Status:** procedure, current — the process half of contributing · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

Welcome to the OciDeck project! We appreciate your interest in contributing. This document outlines how to contribute effectively to the project.

> **There are two contributing documents, and this is the process one.** This
> file covers issue reporting, review, branch naming, the (absent) release
> process and the Code of Conduct, and ships inside the app as a readable
> document. Its companion, [`../CONTRIBUTING.md`](../CONTRIBUTING.md) in the
> repository root, covers the commands: the quality gate, each `make` target,
> and the localisation tooling. It is not bundled with the app. Neither replaces
> the other. *(Noted 2026-07-22: the two had grown apart without either
> mentioning that the other existed.)*

## How to Contribute

### Reporting Issues

Before creating a new issue, please:
1. Search existing issues to avoid duplicates
2. Check whether you are on the latest `main` — there are no released versions
3. Include detailed information about your environment and steps to reproduce

When reporting bugs or requesting features:
- Use clear and descriptive titles
- Provide detailed descriptions with examples when possible
- Include screenshots or screen recordings where relevant
- Specify your operating system, your Flutter/Dart versions, and the commit hash
  you are on (the app has no version number to read off)

### Pull Request Process

1. Fork the repository and create a feature branch
2. Make your changes following project conventions
3. Run `make check` to ensure all tests pass
4. Add or update documentation as needed
5. Create a descriptive pull request with:
   - Clear title and description
   - Reference to related issues
   - Explanation of what changed and why

### Code Style and Conventions

Our codebase follows strict conventions:
- Dart formatting: `dart format` (enforced by `make format-check`, which runs
  locally and, since #751, in CI on every pull request as part of `make check`)
- No raw `print()` statements, use logging instead  
- Strict type checking with `strict-casts`, `strict-raw-types`, `strict-inference`
- Layering rules: models don't import UI layers
- Method length limit of 150 lines per method/function

### Testing Requirements

All code changes should include:
- Unit tests for new functionality
- Widget tests where behaviour is visible in the UI (there is no
  `integration_test/` suite)
- Coverage maintained at or above the enforced floor (80% line coverage, checked by `make coverage`)
- Test the specific behavior being changed

## Development Setup

### Prerequisites

- **Flutter 3.44.7** (stable), with its bundled Dart 3.12.2 — see
  [BUILD.md](BUILD.md), which is the authority on the toolchain pin and on why
  `make format-check` needs the exact version while building does not
- macOS, Windows, or Linux desktop toolchain for your target platform  
- For web development: `make build-web` is available with hardened CSP

### Getting Started

```bash
# Clone the repository
git clone https://pawprint.vigilis.online/LibreKAT/Ocideck.git

# Install dependencies
make setup

# Run tests to verify everything works
make check
```

### Running Locally

```bash
# Run on desktop (macOS, Windows, Linux)
flutter run -d macos  # or windows/linux

# Build the hardened web bundle, then serve build/web/ from any static host
make build-web
# e.g. (cd build/web && python3 -m http.server 8080)
# For a live-reload dev loop, use: flutter run -d chrome
```

## Code Review Process

All contributions undergo code review. During review:
1. The code is checked for adherence to conventions and best practices
2. Functionality is verified through testing
3. Security considerations are evaluated
4. Documentation updates are reviewed
5. Performance implications are considered

Reviewers look for:
- Clean, readable code that follows established patterns
- Proper error handling 
- Efficient resource usage
- Clear documentation of complex logic
- Consistent naming conventions

## Branch Naming Conventions

Use descriptive branch names with one of the prefixes this repository actually
uses, measured over the last 200 merges to `main`:

| Prefix | Used for | Merges |
| --- | --- | --- |
| `fix/` | bug fixes | 63 |
| `feat/` | new features | 48 |
| `docs/` | documentation | 21 |
| `land/` | landing work split across branches | 11 |
| `test/` | tests only | 8 |
| `refactor/` | restructuring, no behaviour change | 8 |
| `chore/` | tooling and housekeeping | 3 |
| `sec/` | security work | 2 |

*(Corrected 2026-07-22: this prescribed `feature/` and `bugfix/`, which appear
zero times in the history — the two most mechanical instructions in this
document, both checkable in one command.)*

## Issue Tracking

We use the project's issue tracker on the Forgejo instance that hosts the
repository to track bugs, enhancements, and feature requests. Issues are
labelled with the tracker's own label set:

- **`bug`** — defects in functionality
- **`enhancement`** — improvements and new capabilities
- **`docs`** — documentation
- **`security`** / **`privacy`** — the two that sort above everything else
- **`triage`** — read but not yet weighed
- **`accepted`** / **`declined`** / **`needs-info`** / **`duplicate`** — the
  outcome of triage

*(Corrected 2026-07-22: this listed `Feature` and `Documentation`, which are not
labels on this tracker, and omitted `privacy` and the whole triage set.)*

So: you file an issue, it gets `triage`, and it leaves that state with a written
reason. `declined` is a real outcome and not a euphemism for silence — an issue
that will not be built is closed and says why. There is one maintainer, so
expect the assessment to take days rather than hours.

**Looking for somewhere to start?** Issues labelled `good first issue` are
small, self-contained, and do not require knowing the rest of the codebase
first. If none are open, say so in a new issue and one will be found — that is a
reasonable thing to ask for, not an imposition. *(Added 2026-07-22: the labels
already encoded a decision path, but only as label names, so a newcomer could
not tell whether a proposal gets an answer or disappears.)*

## Release Process

**Nothing has been released yet** — `git tag` carries no version and the version
sits at `0.1.0+1`. Changes are merged to `main` through pull requests, and until
a tag exists you run what you build.

The machinery for the first one is in place, though: pushing a `v*` tag runs
`.forgejo/workflows/release.yml`, which builds the web, macOS and Linux
artifacts on the forge, collects the Windows build from the GitHub mirror,
publishes them as a Forgejo release with the SBOM and `SHA256SUMS`, and puts the
web bundle live. The full sequence — including what to check before tagging —
is [BUILD.md § Cutting a release](BUILD.md#cutting-a-release).

Versioning follows [Semantic Versioning](https://semver.org/); what a version
change means for existing decks belongs in
[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md).

## Code of Conduct

All contributors are expected to follow our code of conduct, and to commit to the
[core values of Stichting LibreKAT](../CODE_OF_CONDUCT.md#our-core-values)
(published at [librekat.nl](https://librekat.nl/en/over/)):
- Be respectful and inclusive to others
- Focus on constructive feedback and improvement 
- Avoid personal attacks or discriminatory behavior
- Maintain professional standards in communications
- Work in a **Just Culture**: mistakes are information, not offences. Report your
  own errors and other people's early; we fix the system before we correct the
  person. See the [Just Culture](../CODE_OF_CONDUCT.md#just-culture) section of
  the Code of Conduct.

## Contact

For questions about contributing, open an issue in the [Forgejo tracker](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues). That is
the only channel; security reports are the exception and follow
[SECURITY.md](../SECURITY.md).

## License

By contributing to OciDeck, you agree that your contributions will be licensed under the EUPL-1.2 license.