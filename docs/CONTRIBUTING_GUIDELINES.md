# OciDeck — Contributing Guidelines

Welcome to the OciDeck project! We appreciate your interest in contributing. This document outlines how to contribute effectively to the project.

## How to Contribute

### Reporting Issues

Before creating a new issue, please:
1. Search existing issues to avoid duplicates
2. Check if you're using the latest version of OciDeck
3. Include detailed information about your environment and steps to reproduce

When reporting bugs or requesting features:
- Use clear and descriptive titles
- Provide detailed descriptions with examples when possible
- Include screenshots or screen recordings where relevant
- Specify your operating system, Flutter/Dart versions, and OciDeck version

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
- Dart formatting: `dart format` (ensured by CI)
- No raw `print()` statements, use logging instead  
- Strict type checking with `strict-casts`, `strict-raw-types`, `strict-inference`
- Layering rules: models don't import UI layers
- Method length limit of 150 lines per method/function

### Testing Requirements

All code changes should include:
- Unit tests for new functionality
- Integration tests where appropriate  
- Coverage maintained at or above current levels (73% floor)
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

# Run web version  
make build-web && make serve-web
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

We use GitHub issues to track bugs, enhancements, and feature requests. 
Issues are categorized by:
- **Bug**: Defects in functionality
- **Enhancement**: Improvements to existing features  
- **Feature**: New capabilities being added
- **Documentation**: Updates needed for documentation
- **Security**: Security-related matters

## Release Process

1. Changes are merged to the main branch through pull requests
2. Version bumps follow semantic versioning (SemVer)
3. Release candidates are tested internally before final release  
4. Documentation is updated in conjunction with releases
5. Assets and binaries are built for all supported platforms

## Code of Conduct

All contributors are expected to follow our code of conduct:
- Be respectful and inclusive to others
- Focus on constructive feedback and improvement 
- Avoid personal attacks or discriminatory behavior
- Maintain professional standards in communications

## Contact

For questions about contributing, contact the project maintainers through GitHub issues or the appropriate communication channels.

## License

By contributing to OciDeck, you agree that your contributions will be licensed under the EUPL-1.2 license.