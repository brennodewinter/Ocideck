# OciDeck — Contributing Guidelines

Welcome to the OciDeck project! We appreciate your interest in contributing. This document outlines how to contribute effectively to the project.

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
- Dart formatting: `dart format` (enforced by `make format-check`, which you run
  locally — the CI workflows are defined but no runner executes them)
- No raw `print()` statements, use logging instead  
- Strict type checking with `strict-casts`, `strict-raw-types`, `strict-inference`
- Layering rules: models don't import UI layers
- Method length limit of 150 lines per method/function

### Testing Requirements

All code changes should include:
- Unit tests for new functionality
- Widget tests where behaviour is visible in the UI (there is no
  `integration_test/` suite)
- Coverage maintained at or above the enforced floor (78% line coverage, checked by `make coverage`)
- Test the specific behavior being changed

## Development Setup

### Prerequisites

- Flutter 3.44.6 (stable) / Dart 3.12.2
- macOS, Windows, or Linux desktop toolchain for your target platform  
- For web development: `make build-web` is available with hardened CSP

### Getting Started

```bash
# Clone the repository
git clone <repository-url>

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

Use descriptive branch names following this pattern:
- `feature/short-description` (for new features)
- `bugfix/issue-number-short-description` (for bug fixes)  
- `docs/update-documentation` (for documentation changes)
- `security/patch-name` (for security-related work)

## Issue Tracking

We use the project's issue tracker on the Forgejo instance that hosts the
repository to track bugs, enhancements, and feature requests. Issues are
categorized by:
- **Bug**: Defects in functionality
- **Enhancement**: Improvements to existing features  
- **Feature**: New capabilities being added
- **Documentation**: Updates needed for documentation
- **Security**: Security-related matters

## Release Process

**There is no release process yet, because there has been no release.** `git tag`
is empty and the version sits at `0.2.0+1`. Changes are merged to `main` through
pull requests and that is the whole of it; you run what you build.

The release workflow in `.github/workflows/` is written but has never fired — it
triggers on a `v*` tag. When the project does adopt a release scheme, this
section and [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) are where it gets written
down.

## Code of Conduct

All contributors are expected to follow our code of conduct:
- Be respectful and inclusive to others
- Focus on constructive feedback and improvement 
- Avoid personal attacks or discriminatory behavior
- Maintain professional standards in communications

## Contact

For questions about contributing, open an issue in the Forgejo tracker. That is
the only channel; security reports are the exception and follow
[SECURITY.md](../SECURITY.md).

## License

By contributing to OciDeck, you agree that your contributions will be licensed under the EUPL-1.2 license.