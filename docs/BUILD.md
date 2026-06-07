# OciDeck — Build & Release

How to build OciDeck from source and produce distributable apps.

## Prerequisites

- **Flutter** 3.44+ (stable), **Dart** 3.12+. Check with `flutter --version`.
- A desktop toolchain for your target:
  - **macOS**: Xcode + CocoaPods.
  - **Windows**: Visual Studio with the "Desktop development with C++" workload.
  - **Linux**: see Flutter's Linux desktop prerequisites (GTK, clang, ninja, etc.).
- Enable the desktop target once if needed, e.g. `flutter config --enable-macos-desktop`.

## Get dependencies

```sh
make setup        # flutter pub get
```

OciDeck uses two **vendored plugin forks** under `third_party/`, wired through
`pubspec.yaml` (a path dependency for `desktop_multi_window`) and
`dependency_overrides` (`screen_retriever_macos`, and a pin of
`video_player_avfoundation`). `flutter pub get` resolves these automatically — no
extra steps. See [`ARCHITECTURE.md`](ARCHITECTURE.md#vendored-forks).

## Run

```sh
flutter run -d macos     # or -d windows / -d linux
```

## Quality gate

```sh
make check        # format-check + flutter analyze + full test suite
```

## Building release apps

```sh
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Artifacts land under `build/<platform>/`.

### macOS notes

- **Swift Package Manager is disabled** for this project (`flutter:` →
  `config: enable-swift-package-manager: false` in `pubspec.yaml`); CocoaPods is
  used instead. The "plugin does not support Swift Package Manager" message
  during a build is therefore expected and harmless.
- **`video_player_avfoundation` is pinned** (see `dependency_overrides`) because a
  newer release ships a Swift module whose private Objective-C dependency isn't
  packaged correctly by CocoaPods on recent Xcode.
- **CocoaPods + Ruby locale**: on some setups `pod install` (run by
  `flutter build macos`) fails with `Encoding::CompatibilityError` /
  "Unicode Normalization not appropriate for ASCII-8BIT". This is a Ruby/CocoaPods
  locale issue, not a project problem. Fix it by forcing a UTF-8 locale:

  ```sh
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  flutter build macos --release
  ```

- **Distribution**: code-sign and notarize the `.app` for distribution outside
  the App Store (Developer ID + `notarytool`). This is environment-specific and
  not automated here.

### Windows / Linux notes

- Windows: distribute the contents of `build/windows/x64/runner/Release/` (or
  package with MSIX/an installer).
- Linux: distribute `build/linux/x64/release/bundle/` (or package as a
  Flatpak/AppImage/Snap as you prefer).

## CI

`.github/workflows/ci.yml` runs `make check` on Ubuntu for every push and pull
request. It does not build native binaries; it validates formatting, static
analysis, and the test suite (which are platform-independent).
