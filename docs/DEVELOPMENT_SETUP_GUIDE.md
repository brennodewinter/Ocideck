# OciDeck — Development Setup Guide

> **Status:** procedure, current · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

This document provides detailed instructions for setting up a development environment for OciDeck.

## Overview

Setting up a proper development environment is crucial for contributing to OciDeck or extending its functionality. This guide covers all necessary steps from system preparation to running the application locally.

## Prerequisites

### System Requirements

- **Operating System**: 
  - macOS (recent versions with Apple Silicon or Intel support)
  - Windows 10 or newer
  - Linux (modern distributions with GTK environment)

- **Hardware**:
  - Minimum 4GB RAM (8GB+ recommended)  
  - Sufficient disk space for Flutter SDK and dependencies

### Software Dependencies

- **Flutter 3.44.9** (stable) — the pinned version. Use the `dart` that
  ships inside it (3.12.2) rather than a separately installed one.
  [BUILD.md](BUILD.md) is the authority here and explains why the exact version
  matters for `make format-check` but not for building.
- **Git**: any recent version. (The *app's* git integration requires 2.19+, see
  `kMinGitVersion`; that is a runtime requirement, not a build one.)
- **Xcode Command Line Tools** (macOS only)  
- **Visual Studio with C++ workload** (Windows only)
- **Linux Build Dependencies**: GTK, clang, ninja, etc.

## Installation Steps

### Step 1: Install Flutter SDK

1. Download Flutter SDK from [flutter.dev](https://flutter.dev/docs/get-started/install)
2. Extract to a permanent location:
   ```bash
   cd ~
   tar xf flutter_macos_3.44.9-stable.tar.xz  # macOS example
   ```

3. Add Flutter to PATH in your shell profile (.zshrc, .bash_profile):
   ```bash
   export PATH="$PATH:$HOME/flutter/bin"
   ```

4. Verify installation:
   ```bash
   flutter --version
   flutter doctor
   ```

### Step 2: Install Platform-Specific Tools

#### macOS Setup
```bash
# Install Xcode command line tools  
xcode-select --install

# Install CocoaPods (required for iOS/Mac builds)
sudo gem install cocoapods

# Install cmake — the dartcv4 native-assets build hook needs it on every
# `flutter test`/`make check`, not just for release builds (see docs/CHECKS.md)
brew install cmake
```

#### Windows Setup
1. Install Visual Studio with "Desktop development with C++" workload
2. Install Chocolatey package manager if needed:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

#### Linux Setup  
```bash
# Install required packages (Ubuntu/Debian example)
sudo apt update
sudo apt install curl git unzip clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++6
```

### Step 3: Clone the Repository

```bash
git clone https://pawprint.vigilis.online/LibreKAT/Ocideck.git
cd Ocideck
```

### Step 4: Setup Dependencies

```bash
# Get Flutter dependencies  
make setup

# Or manually:
flutter pub get
```

The project uses vendored plugin forks that are automatically resolved through `pubspec.yaml`.

## Environment Configuration

### Setting Up IDE

#### VS Code (Recommended)
1. Install the Dart and Flutter extensions from the marketplace
2. Configure Flutter SDK path in VS Code settings:  
   ```json
   {
     "dart.flutterSdkPath": "/path/to/flutter"
   }
   ```

#### IntelliJ IDEA
1. Install Dart and Flutter plugins
2. Configure project SDKs for both Dart and Flutter

### Environment Variables

Some features may require specific environment variables:
- `FLUTTER_ROOT` (if not in PATH)  
- Custom build flags for development builds

## Running the Application

### Local Development Run

#### Desktop Platforms
```bash
# Run on macOS
flutter run -d macos

# Run on Windows  
flutter run -d windows

# Run on Linux
flutter run -d linux
```

#### Web Platform
```bash
# Build the hardened web bundle, then serve build/web/ from any static host
make build-web
# e.g. (cd build/web && python3 -m http.server 8080)

# Or, for a live-reload dev loop:
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8080
```

### Debugging Configuration

#### VS Code Launch Configurations
Create `.vscode/launch.json` for debugging:

```json
{
  "version": "0.1.0",
  "configurations": [
    {
      "name": "Debug OciDeck (macOS)",
      "request": "launch", 
      "type": "dart",
      "program": "lib/main.dart",
      "device_id": "macos"
    }
  ]
}
```

### Development Build Variants

These are Flutter's stock modes, not project-specific variants:
- **Development**: Debug builds
- **Release**: Optimized builds, what `make build-*` produces
- **Profile**: Builds with performance profiling enabled

## Testing Setup

### Running Tests

```bash
# Run all tests (randomized order)
make test

# Run specific test groups
make test-contracts    # Markdown round-trip and field migration tests
make test-preview      # Slide rendering and preview tests  
make test-export       # Export functionality tests
make test-state        # State management tests
make test-services     # Service layer tests
make test-presenter    # Presenter functionality tests

# Run quality gate checks
make check             # format-check + analyze + conventions + method-length + dead-code + coverage
make check-full        # Plus license, SBOM freshness, bundled-JS CVEs, web hardening, deps report
```

### Test Environment Requirements

- Flutter testing framework  
- Dart VM with proper isolate handling
- Mock services for network operations
- Proper file system access permissions for tests  

## Build Process

### Production Builds

```bash
# Web build (hardened)
make build-web

# Desktop builds
make build-macos
make build-windows 
make build-linux

# All platforms at once
make build-all

# Complete release (web + native desktop)
make build-release
```

### Build Configuration

The build system uses:
- `Makefile` for standardized targets  
- `pubspec.yaml` for dependency management
- Hardened web builds with CSP enforcement

## Development Workflow

### Branch Management

Recommended workflow patterns:
1. **Feature branches**: Create from main for new features
2. **Bug fixes**: Branch from `main` — there is no released version to branch from
3. **Documentation**: Separate branch if substantial changes needed

### Code Quality Standards

The development workflow enforces:
- `dart format` compliance (via make format-check)
- Static analysis (`flutter analyze --fatal-infos`)
- Unit and widget tests for all new features  
- Coverage minimum of 80% line coverage (enforced by `make coverage`)
- Convention enforcement through check_conventions

### Version Control Guidelines  

1. **Commit Messages**: Follow conventional commit format
2. **Branch Naming**: Use descriptive names per contributing guidelines
3. **Pull Requests**: Include detailed descriptions and test plans
4. **Code Reviews**: Aimed for on every change, but not enforced by the repository

## Troubleshooting Common Issues

### Flutter/Toolchain Problems

1. **Version Mismatch**:
   ```bash
   # Check tool versions
   flutter --version
   
   # Ensure correct Flutter version via asdf or manual install
   ```

2. **Dependencies Not Found**:  
   ```bash
   # Clean and reinstall dependencies
   flutter pub cache repair
   flutter pub get
   ```

### Platform-Specific Issues

#### macOS
- CocoaPods issues: `pod install` in `ios/` directory if needed  
- Xcode permissions: Ensure full disk access for Flutter apps

#### Windows
- Visual Studio C++ build tools required
- Anti-virus software might interfere with builds  

#### Linux
- GTK library versions must be compatible  
- Desktop environment requirements met

### Performance Optimization During Development

1. **Debug Build**: Use debug mode for development iterations
2. **Selective Testing**: Run only relevant test groups during development  
3. **Cache Management**: Clear Dart/Flutter caches if issues persist
4. **Memory Monitoring**: Watch for memory leaks in long-running sessions

## Advanced Configuration

### Custom Build Flags

There are none. OciDeck has no debug-logging flag, no feature-toggle system and
no performance instrumentation to switch on — the build is what the Makefile
targets produce.

### Vendored plugin forks

OciDeck has no plugin or extension mechanism — nothing loads third-party code at
runtime. What `third_party/` contains is something else: forks of two Flutter
plugins (`screen_retriever_macos`, `desktop_multi_window`) pinned through
`dependency_overrides` in `pubspec.yaml`. Change one and you rebuild the app;
there is no separate package to publish.

## Tooling and support

### Development Tools

Recommended tools for development:
- IDE with Dart/Flutter support (VS Code, IntelliJ)
- Terminal multiplexer (tmux/screen) 
- Git GUI clients for visualization
- Performance profiling tools  

### Contribution Guidelines

Refer to the contributing guidelines document for complete contribution workflow.

This setup guide should enable you to fully develop and test OciDeck locally. If
issues persist, see [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) or open
an issue in the [Forgejo tracker](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues) — that is the only contact channel.