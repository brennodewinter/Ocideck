@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards Phase 1 of the Linux install route (#1227): the release ships an
/// AppImage, a .deb and an .rpm next to the tarball, built by
/// `scripts/package_linux.sh` and wired into the Linux release job.
///
/// The real packages only exist after a `v*` tag is built on Linux, so no
/// `flutter test` ever produces one. What is checkable offline — the same scope
/// as `release_package_layout_test.dart` — is that the wiring, the script and
/// the packaging metadata stay internally consistent: the workflow calls the
/// packager and uploads every artifact it makes, the script names those exact
/// artifacts and declares the right runtime dependencies, and appimagetool is
/// fetched under a checksum rather than trusted blindly.
void main() {
  final releaseYaml = File('.forgejo/workflows/release.yml').readAsStringSync();
  final script = File('scripts/package_linux.sh').readAsStringSync();
  final desktop = File(
    'packaging/linux/com.dewinter.ocideck.desktop',
  ).readAsStringSync();
  final appRun = File('packaging/linux/AppRun').readAsStringSync();
  final pkgbuild = File('packaging/aur/PKGBUILD').readAsStringSync();
  final releaseBody = File('.forgejo/release-body.md').readAsStringSync();

  group('the release workflow builds and ships the Linux packages', () {
    test('the Linux job installs rpmbuild (via the rpm package)', () {
      // dpkg-deb is in the base system and appimagetool is fetched by the
      // script, but rpmbuild is not — the job must add it.
      expect(
        RegExp(r'apt-get install[^\n]*\brpm\b').hasMatch(releaseYaml),
        isTrue,
        reason: 'The Linux job no longer installs `rpm` for rpmbuild (#1227).',
      );
    });

    test('the Linux job installs file (appimagetool needs it)', () {
      // appimagetool shells out to `file` and refuses to run without it, but a
      // minimal ubuntu image has no `file`. Missing it made the whole Linux job
      // fail, which skips `publiceren` and publishes no release at all (v0.3.3).
      expect(
        RegExp(r'apt-get install[^\n]*\bfile\b').hasMatch(releaseYaml),
        isTrue,
        reason: 'The Linux job no longer installs `file` for appimagetool.',
      );
    });

    test('the Linux job runs the packager', () {
      expect(
        releaseYaml.contains('make package-linux VERSION='),
        isTrue,
        reason: 'The Linux job no longer calls `make package-linux` (#1227).',
      );
    });

    test('appimagetool is pinned by a 64-hex sha256, not floated', () {
      final match = RegExp(
        r'APPIMAGETOOL_SHA256:\s*([0-9a-f]{64})',
      ).firstMatch(releaseYaml);
      expect(
        match,
        isNotNull,
        reason:
            'The Linux job must pin appimagetool by sha256 (a rolling upstream '
            'tag, so the hash is the pin). Missing APPIMAGETOOL_SHA256 (#1227).',
      );
      expect(
        releaseYaml.contains('APPIMAGETOOL_URL:'),
        isTrue,
        reason: 'appimagetool has a sha256 but no URL to fetch from.',
      );
    });

    test('every package the job makes is uploaded as an artifact', () {
      // Filenames intentionally use each format's own arch label: amd64 for the
      // .deb (Debian), x86_64 for the .rpm and AppImage.
      for (final asset in [
        r'dist/ocideck-linux-x64-${{ env.VERSIE }}.tar.gz',
        r'dist/ocideck-linux-amd64-${{ env.VERSIE }}.deb',
        r'dist/ocideck-linux-x86_64-${{ env.VERSIE }}.rpm',
        r'dist/ocideck-linux-x86_64-${{ env.VERSIE }}.AppImage',
      ]) {
        expect(
          releaseYaml.contains(asset),
          isTrue,
          reason: 'The Linux artifact upload no longer lists `$asset` (#1227).',
        );
      }
    });
  });

  group('the packager names the same artifacts and real dependencies', () {
    test('it writes the three versioned package filenames', () {
      for (final name in [
        r'ocideck-linux-amd64-$VERSION.deb',
        r'ocideck-linux-x86_64-$VERSION.rpm',
        r'ocideck-linux-x86_64-$VERSION.AppImage',
      ]) {
        expect(
          script.contains(name),
          isTrue,
          reason: 'package_linux.sh no longer emits `$name`.',
        );
      }
    });

    test('the .deb declares the runtime libraries the bundle links', () {
      final depends = RegExp(r'Depends:[^\n]*').firstMatch(script)?.group(0);
      expect(
        depends,
        isNotNull,
        reason: 'No Depends line in the .deb control.',
      );
      for (final lib in ['libgtk-3-0', 'libsecret-1-0', 'liblzma5']) {
        expect(
          depends,
          contains(lib),
          reason: 'The .deb Depends omits `$lib` (a linked runtime library).',
        );
      }
    });

    test('the AppImage build requires the file tool up front', () {
      // appimagetool invokes `file`; the packager checks for it before running
      // so a missing tool fails with a clear message instead of a cryptic
      // appimagetool error deep in the run (broke v0.3.3).
      expect(
        RegExp(r'require file\b').hasMatch(script),
        isTrue,
        reason:
            'build_appimage no longer checks for `file` before invoking '
            'appimagetool, which needs it.',
      );
    });

    test('appimagetool is verified against its sha256 before use', () {
      expect(
        script.contains('sha256sum -c'),
        isTrue,
        reason:
            'package_linux.sh runs a fetched appimagetool without a checksum '
            'check — the pin is only real if it is verified.',
      );
    });

    test('it packages the desktop entry and bundled icon', () {
      // The script keys the desktop entry and themed icon off the application
      // id and installs the .desktop file it builds from it.
      expect(
        script.contains('APP_ID="com.dewinter.ocideck"'),
        isTrue,
        reason: 'The packager no longer uses the com.dewinter.ocideck app id.',
      );
      expect(script.contains(r'$APP_ID.desktop'), isTrue);
      expect(
        script.contains('data/icons/app_icon.png'),
        isTrue,
        reason: 'The icon should come from the bundle, which already ships it.',
      );
    });
  });

  group('the desktop entry and AppRun are well formed', () {
    test('the desktop entry launches the binary with the app-id icon', () {
      expect(desktop.startsWith('[Desktop Entry]'), isTrue);
      expect(desktop, contains('Type=Application'));
      expect(desktop, contains('Exec=ocideck'));
      // The GTK runner sets its default icon name to the application id, so the
      // themed icon and the desktop entry must both key off it.
      expect(desktop, contains('Icon=com.dewinter.ocideck'));
      // Categories must be a valid, semicolon-terminated list.
      expect(
        RegExp(r'Categories=[^\n]+;\s*$', multiLine: true).hasMatch(desktop),
        isTrue,
      );
    });

    test('AppRun execs the bundle binary', () {
      expect(
        RegExp(r'exec\s+"\$\{?HERE\}?/ocideck"').hasMatch(appRun),
        isTrue,
        reason: 'AppRun must exec the ocideck binary from the AppDir root.',
      );
    });
  });

  group('the AUR PKGBUILD tracks our own release', () {
    test('it is the -bin package that provides ocideck', () {
      expect(pkgbuild, contains('pkgname=ocideck-bin'));
      expect(pkgbuild, contains("provides=('ocideck')"));
    });

    test('its source is our forge release tarball', () {
      expect(
        pkgbuild.contains(r'ocideck-linux-x64-${pkgver}.tar.gz'),
        isTrue,
        reason: 'The PKGBUILD must fetch our own release tarball.',
      );
      expect(pkgbuild.contains(r'releases/download/v${pkgver}'), isTrue);
    });

    test('it depends on the Arch names for the linked libraries', () {
      final depends = RegExp(
        r'depends=\([^)]*\)',
      ).firstMatch(pkgbuild)?.group(0);
      expect(depends, isNotNull);
      for (final dep in ['gtk3', 'libsecret', 'xz']) {
        expect(depends, contains(dep));
      }
    });
  });

  test('the release notes list the new Linux downloads', () {
    for (final asset in [
      'ocideck-linux-x86_64-@VERSIE@.AppImage',
      'ocideck-linux-amd64-@VERSIE@.deb',
      'ocideck-linux-x86_64-@VERSIE@.rpm',
    ]) {
      expect(
        releaseBody.contains(asset),
        isTrue,
        reason: 'The release notes no longer mention `$asset` (#1227).',
      );
    }
  });
}
