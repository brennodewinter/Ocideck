@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Windows installer (#1208): `packaging/windows/ocideck.iss`, built
/// by `scripts/build_windows_installer.sh` behind `make build-windows-installer`.
///
/// The installer itself only exists after Inno Setup has run on Windows, so no
/// `flutter test` ever produces one — the same situation
/// `linux_packaging_test.dart` is in, and the same answer: pin offline what can
/// drift. Three things matter here.
///
/// 1. The installer and `windows/file-associations.reg` must keep declaring the
///    *same* file associations. They are two routes to one behaviour (installed
///    versus raw bundle), and the .reg file already rotted once by being the
///    only copy of a path.
/// 2. The installer must wrap `make build-windows`'s output and nothing else —
///    a hand-picked file list is how a packager starts shipping a stale binary.
/// 3. It must stay a dumb, offline installer. SECURITY.md promises OciDeck does
///    not phone home; an update check inside the installer would quietly break
///    that promise, and it is exactly the kind of convenience that creeps in.
void main() {
  final iss = File('packaging/windows/ocideck.iss').readAsStringSync();
  final reg = File('windows/file-associations.reg').readAsStringSync();
  final script = File('scripts/build_windows_installer.sh').readAsStringSync();
  // The header comment explains at length which signing routes are refused and
  // why, so a check for "does it accept a .pfx" has to read the commands, not
  // the prose about them.
  final scriptCode = script
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
  final makefile = File('Makefile').readAsStringSync();

  group('the installer and the .reg file declare the same associations', () {
    test('both use the OciDeck.Package ProgID', () {
      expect(
        reg.contains(r'Software\Classes\OciDeck.Package'),
        isTrue,
        reason: 'windows/file-associations.reg no longer uses OciDeck.Package.',
      );
      expect(
        iss.contains('#define ProgId "OciDeck.Package"'),
        isTrue,
        reason:
            'The installer no longer registers the ProgID the .reg file uses, '
            'so an installed OciDeck and a hand-imported one would disagree.',
      );
    });

    test('.ocideck points at the ProgID in both', () {
      expect(
        reg.contains(r'[HKEY_CURRENT_USER\Software\Classes\.ocideck]'),
        isTrue,
      );
      expect(
        RegExp(
          r'Subkey:\s*"Software\\Classes\\\.ocideck".*ValueData:\s*"\{#ProgId\}"',
        ).hasMatch(iss),
        isTrue,
        reason: 'The installer no longer makes .ocideck open with OciDeck.',
      );
    });

    test(
      '.md only joins OpenWithProgids in both — it never takes the default',
      () {
        // Taking over .md would hijack every Markdown file on the machine. Both
        // routes deliberately stop at the "Open with…" list.
        expect(reg.contains(r'Software\Classes\.md\OpenWithProgids'), isTrue);
        expect(
          RegExp(
            r'Subkey:\s*"Software\\Classes\\\.md\\OpenWithProgids"',
          ).hasMatch(iss),
          isTrue,
          reason:
              'The installer no longer registers .md as an "Open with" option.',
        );
        expect(
          RegExp(
            r'Subkey:\s*"Software\\Classes\\\.md"[^\n]*ValueData',
          ).hasMatch(iss),
          isFalse,
          reason:
              'The installer sets a default handler for .md — that hijacks every '
              'Markdown file on the machine. Only OpenWithProgids belongs here.',
        );
      },
    );

    test('both open the file that was double-clicked, via the same exe', () {
      expect(reg.contains(r'ocideck.exe\" \"%1\"'), isTrue);
      expect(
        iss.contains(r'ValueData: """{app}\{#ExeName}"" ""%1"""'),
        isTrue,
        reason:
            'The shell\\open\\command no longer passes %1, so double-clicking a '
            'deck would open OciDeck on an empty document.',
      );
      expect(
        iss.contains('#define ExeName "ocideck.exe"'),
        isTrue,
        reason:
            'The installer no longer targets ocideck.exe — the binary name '
            'set by windows/CMakeLists.txt (BINARY_NAME).',
      );
    });
  });

  group('the installer wraps the build output and nothing else', () {
    test('it takes its files from the make build-windows output directory', () {
      expect(
        iss.contains(
          r'#define BundleDir "..\..\build\windows\x64\runner\Release"',
        ),
        isTrue,
        reason:
            'The installer no longer sources build/windows/x64/runner/Release '
            '— the directory `make build-windows` writes.',
      );
    });

    test('it copies that whole directory rather than a hand-picked list', () {
      // A file list would silently omit a newly added DLL or asset.
      final sources = RegExp(
        r'^Source:\s*(.+)$',
        multiLine: true,
      ).allMatches(iss).map((m) => m.group(1)!).toList();
      expect(sources, hasLength(1), reason: 'Sources: $sources');
      expect(sources.single, contains(r'"{#BundleDir}\*"'));
      expect(sources.single, contains('recursesubdirs'));
    });

    test('the script refuses to package a bundle that is not there', () {
      expect(
        script.contains("run 'make build-windows' first"),
        isTrue,
        reason:
            'Without this guard the packager builds an empty installer when the '
            'bundle is missing.',
      );
    });

    test('the version comes from pubspec.yaml, not from a second copy', () {
      expect(
        script.contains('pubspec.yaml'),
        isTrue,
        reason: 'The packager no longer reads the version from pubspec.yaml.',
      );
      expect(
        iss.contains('#ifndef AppVersion'),
        isTrue,
        reason:
            'The .iss hardcodes a version instead of taking /DAppVersion from '
            'the packager — a second place to forget to bump.',
      );
    });

    test('the script and the .iss agree on the installer filename', () {
      expect(
        iss.contains(
          'OutputBaseFilename=ocideck-windows-x64-setup-{#AppVersion}',
        ),
        isTrue,
      );
      expect(
        script.contains(r'$OUT/ocideck-windows-x64-setup-$VERSION.exe'),
        isTrue,
        reason:
            'The script looks for a different filename than Inno Setup writes, '
            'so it would report a missing installer after a successful build.',
      );
    });

    test('make build-windows-installer runs the packager', () {
      expect(
        makefile.contains('scripts/build_windows_installer.sh'),
        isTrue,
        reason: 'The Makefile target no longer calls the packager (#1208).',
      );
    });
  });

  group('it stays a dumb, offline installer', () {
    test('nothing in it downloads or checks for a version', () {
      // The Inno ecosystem's usual downloaders, plus the plain script hooks that
      // would reach the network from [Code].
      for (final forbidden in [
        'idpAddFile', // Inno Download Plugin
        'DownloadTemporaryFile', // Inno 6's built-in downloader
        'CreateDownloadPage',
        'WinHttp',
        'URLDownloadToFile',
      ]) {
        expect(
          iss.contains(forbidden),
          isFalse,
          reason:
              'The installer uses `$forbidden`, so it reaches the network. '
              'SECURITY.md promises OciDeck does not phone home and that fixes '
              'arrive by rebuilding — an installer that updates itself breaks '
              'that promise (#1208, and the boundary the Bewaker set).',
        );
      }
    });

    test('it runs no custom code at all', () {
      // No [Code] section means there is no place for an update check to hide.
      expect(
        RegExp(r'^\[Code\]', multiLine: true).hasMatch(iss),
        isFalse,
        reason:
            'The installer grew a [Code] section. That is where a version check '
            'or a phone-home would live; keep it a declarative script.',
      );
    });
  });

  group('signing is optional, and never silently absent', () {
    test('an unsigned build warns instead of failing', () {
      // A developer without a certificate must not be blocked, but must also
      // never believe they produced a signed installer.
      expect(
        script.contains('WARNING — this installer is NOT code-signed'),
        isTrue,
        reason:
            'The packager no longer warns when it produced an unsigned '
            'installer, so an unsigned one could ship unnoticed (#1013/#1208).',
      );
    });

    test('the signing material is a store thumbprint, never a file or password', () {
      // Since June 2023 a publicly trusted code-signing key must live on a
      // hardware token or HSM. Accepting a .pfx + password would invite exactly
      // the runner secret #1013 rejected.
      expect(scriptCode.contains('OCIDECK_WIN_SIGN_SHA1'), isTrue);
      expect(
        RegExp(r'/f\s|\.pfx|/p\s').hasMatch(scriptCode),
        isFalse,
        reason:
            'The packager accepts a certificate file or password. Signing must '
            'go through a hardware token in the certificate store, so no '
            'signing secret can become an environment variable or a CI secret.',
      );
    });

    test('signatures are timestamped', () {
      // Without a timestamp every signature dies with the certificate, which
      // since March 2026 lasts at most 460 days.
      expect(
        scriptCode.contains('/tr "\$TIMESTAMP_URL" /td SHA256'),
        isTrue,
        reason: 'signtool is invoked without RFC 3161 timestamping.',
      );
    });
  });
}
