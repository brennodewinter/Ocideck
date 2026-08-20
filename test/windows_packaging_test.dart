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
  final mirrorYaml = File('.github/workflows/release.yml').readAsStringSync();
  final forgeYaml = File('.forgejo/workflows/release.yml').readAsStringSync();
  final releaseBody = File('.forgejo/release-body.md').readAsStringSync();
  final pinManifest = File(
    '.github/pinned-ci-versions.json',
  ).readAsStringSync();

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

    test('the .md entry writes an actual value, and Explorer hears it', () {
      // ValueType none creates only the KEY and silently drops ValueName —
      // Explorer reads value NAMES under OpenWithProgids, so the promised
      // "Open with…" entry never existed. Shipped broken once; never again.
      expect(
        RegExp(
          r'OpenWithProgids";\s*ValueType:\s*string;\s*'
          r'ValueName:\s*"\{#ProgId\}"',
        ).hasMatch(iss),
        isTrue,
        reason:
            'The .md OpenWithProgids line no longer writes a named value — '
            'ValueType none is documented to ignore ValueName/ValueData, so '
            'the "Open with…" entry silently never appears.',
      );
      expect(
        iss.contains('ChangesAssociations=yes'),
        isTrue,
        reason:
            'Without ChangesAssociations=yes Explorer is never told to '
            'refresh, so .ocideck keeps a blank icon until re-login.',
      );
    });

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

  // The installer only reaches a user if four places agree on one filename and
  // one ordering: the mirror builds and uploads it, the forge fetches it before
  // it hashes anything, and the release notes offer it. #1583 wired that up; the
  // failure mode it guards is a release that quietly ships one fewer file than
  // it promises — which is exactly what nobody notices until a user asks.
  group('the release chain carries the installer end to end', () {
    const installer = r'ocideck-windows-x64-setup-$VERSIE.exe';

    test("the mirror installs Inno Setup pinned by version and sha256", () {
      expect(
        RegExp(r'INNOSETUP_VERSION:\s*(\d+\.\d+\.\d+)').firstMatch(mirrorYaml),
        isNotNull,
        reason: 'The Windows job no longer pins an Inno Setup version (#1583).',
      );
      expect(
        RegExp(r'INNOSETUP_SHA256:\s*[0-9a-f]{64}').hasMatch(mirrorYaml),
        isTrue,
        reason:
            'Inno Setup is fetched without a sha256, so a replaced release '
            'asset would build silently instead of failing loudly.',
      );
      // Not pinned to one shell's spelling — the step moved from bash to
      // PowerShell to escape MSYS path conversion, and this check is about the
      // property, not the tool: the pin is computed and a mismatch stops the
      // build rather than being printed and ignored.
      expect(
        RegExp(r'Get-FileHash|sha256sum').hasMatch(mirrorYaml),
        isTrue,
        reason:
            'The pinned sha256 of the Inno Setup download is never computed.',
      );
      expect(
        RegExp(
          r'-ne \$env:INNOSETUP_SHA256[\s\S]{0,200}?throw|sha256sum -c',
        ).hasMatch(mirrorYaml),
        isTrue,
        reason:
            'The computed hash is never compared against the pin, or a mismatch '
            'does not fail the step — a pin nobody acts on is decoration.',
      );
    });

    test('that pin is listed in the manifest, at the same version', () {
      final version = RegExp(
        r'INNOSETUP_VERSION:\s*(\d+\.\d+\.\d+)',
      ).firstMatch(mirrorYaml)!.group(1);
      expect(
        pinManifest.contains('"INNOSETUP_VERSION"'),
        isTrue,
        reason:
            'The Inno Setup pin is missing from .github/pinned-ci-versions.json, '
            'so `make check-pins` will never notice it going stale.',
      );
      expect(
        pinManifest.contains('"version": "$version"'),
        isTrue,
        reason:
            'The manifest and the workflow disagree on the Inno Setup version '
            '($version in the workflow).',
      );
    });

    test('the mirror builds the installer before it zips the bundle', () {
      // Anchored on the run line, not the first occurrence: the filename also
      // appears in comments above the step, and an index into a comment lets
      // someone reorder the real steps without tripping this test.
      final buildAt = mirrorYaml.indexOf(
        'bash scripts/build_windows_installer.sh',
      );
      final zipAt = mirrorYaml.indexOf('7z a -tzip');
      expect(buildAt, greaterThan(-1), reason: 'The mirror never builds it.');
      expect(
        buildAt,
        lessThan(zipAt),
        reason:
            'The zip is built before the installer. The packager signs the exe '
            'and DLLs in place when a certificate is configured, so this order '
            'would ship a zip of unsigned binaries next to a signed installer — '
            'two downloads that are not the same build.',
      );
    });

    test('the installer is built with the version from the tag', () {
      // Not from pubspec.yaml: the forge fetches by a name derived from the tag,
      // so a tag that is momentarily ahead of pubspec would produce a file the
      // forge cannot find.
      expect(
        mirrorYaml.contains(
          r'VERSION="${GITHUB_REF_NAME#v}" bash scripts/build_windows_installer.sh',
        ),
        isTrue,
        reason:
            'The mirror lets the packager read pubspec.yaml instead of using '
            'the tag, so the filename can drift from what the forge fetches.',
      );
    });

    test('the mirror uploads it and the forge fetches it, under one name', () {
      expect(
        mirrorYaml.contains(installer),
        isTrue,
        reason: 'The mirror builds the installer but never publishes it.',
      );
      expect(
        forgeYaml.contains(installer),
        isTrue,
        reason:
            'windows-ophalen does not fetch the installer, so it never reaches '
            'the forge release — and never reaches SHA256SUMS.',
      );
    });

    test('the forge waits for BOTH files before it calls the job done', () {
      // A check satisfied by the zip alone would let a half-uploaded mirror run
      // pass, publishing a release with the installer silently missing.
      final have = RegExp(
        r'have_asset\(\)\s*\{(.*?)\n          \}',
        dotAll: true,
      ).firstMatch(forgeYaml);
      expect(have, isNotNull, reason: 'have_asset() no longer parses.');
      expect(
        have!.group(1),
        contains(r'${BESTANDEN[@]}'),
        reason:
            'have_asset checks a single file. It must require every expected '
            'Windows artifact, or a missing installer reads as success.',
      );
    });

    test('the artifact hand-off is not narrowed to the zip', () {
      expect(
        RegExp(
          r'path:\s*ocideck-windows-x64-\*\s*$',
          multiLine: true,
        ).hasMatch(forgeYaml),
        isTrue,
        reason:
            'The upload-artifact glob no longer carries both Windows files, so '
            'the installer is dropped between windows-ophalen and publiceren.',
      );
    });

    // v0.4.7-rc1 hing 1u52m op deze klasse fout: MSYS vertaalde `/VERYSILENT`
    // naar een pad, Inno Setup opende zijn venster, en niemand kon klikken. Wat
    // hem verraderlijk maakt is dat hij op macOS niet bestáát — de rooktoets met
    // een nagemaakte ISCC en signtool draaide vrolijk groen. Alleen een gate op
    // de vorm vangt dit vóór de volgende tag.
    test('the packager shields Windows-style flags from MSYS path conversion', () {
      expect(
        scriptCode.contains('msys_safe()'),
        isTrue,
        reason:
            'The packager no longer defines msys_safe, so `/DAppVersion=…` and '
            'the signtool flags get rewritten into Windows paths under Git Bash.',
      );
      for (final call in ['msys_safe "\$ISCC"', 'msys_safe "\$SIGNTOOL"']) {
        expect(
          scriptCode.contains(call),
          isTrue,
          reason:
              '`$call` is invoked without the MSYS guard. Its /-prefixed flags '
              'will arrive as C:/Program Files/Git/... and be silently ignored.',
        );
      }
    });

    test(
      'the mirror installs Inno Setup without Git Bash, and waits for it',
      () {
        final stap = RegExp(
          r'- name: Inno Setup installeren.*?(?=\n      - name:)',
          dotAll: true,
        ).firstMatch(mirrorYaml);
        expect(
          stap,
          isNotNull,
          reason: 'The Inno Setup step no longer parses.',
        );
        expect(
          stap!.group(0),
          contains('shell: pwsh'),
          reason:
              'The Inno Setup step runs under bash again. MSYS rewrites '
              '/VERYSILENT into a path, the installer opens its window, and the '
              'job hangs until the timeout (v0.4.7-rc1).',
        );
        expect(
          stap.group(0),
          contains('-Wait'),
          reason:
              "Start-Process without -Wait returns as soon as Inno's setup.exe "
              'hands off to its .tmp child, so ISCC can be called before the '
              'install has finished.',
        );
        // The shell fix is worthless if the flags themselves go missing: rc1
        // hung precisely because Inno Setup received no recognised silent-mode
        // flag. /SUPPRESSMSGBOXES keeps an error from raising a dialog.
        for (final vlag in ["'/VERYSILENT'", "'/SUPPRESSMSGBOXES'"]) {
          expect(
            stap.group(0),
            contains(vlag),
            reason:
                '\$vlag is gone from the ArgumentList — the installer opens a '
                'window on the runner and the job hangs until its timeout.',
          );
        }
        expect(
          stap.group(0),
          contains('-PassThru'),
          reason:
              'Start-Process never throws on a non-zero child, and '
              '/SUPPRESSMSGBOXES suppresses exactly the error dialogs — '
              'without -PassThru plus an ExitCode check, a failed install '
              'reads as success and only ISCC fails later, pointing the '
              'wrong way.',
        );
        // The comparison itself, not merely the word: the throw message also
        // says "ExitCode", so a disabled `if (\$false)` would still contain it.
        expect(
          stap.group(0),
          contains('ExitCode -ne 0'),
          reason: 'The -PassThru result is never actually compared.',
        );
      },
    );

    test('the mirror job cannot hang forever or race itself', () {
      expect(
        RegExp(r'timeout-minutes:\s*\d+').hasMatch(mirrorYaml),
        isTrue,
        reason:
            'The Windows job has no timeout-minutes: rc1 proved a hang runs '
            'into the six-hour default, blocking every retrigger meanwhile.',
      );
      expect(
        mirrorYaml.contains('concurrency:'),
        isTrue,
        reason:
            'No concurrency group: the tag push and the forge dispatch can '
            'start two runs that race to upload the same two release assets.',
      );
      expect(
        mirrorYaml.contains('cancel-in-progress: false'),
        isTrue,
        reason:
            'Duplicate runs must QUEUE, not cancel: a cancelled run leaves on '
            'the tag exactly the conclusion windows-ophalen once misread as a '
            'failed build.',
      );
      expect(
        mirrorYaml.contains('Alleen op een tag'),
        isTrue,
        reason:
            'workflow_dispatch accepts any ref; without the tag guard a '
            'manual run on main publishes a fake "main" release on the mirror.',
      );
    });

    test('the forge judges a run only if it belongs to this attempt', () {
      expect(
        forgeYaml.contains('created_at'),
        isTrue,
        reason:
            'run_status no longer reads created_at, so the conclusion of an '
            'OLDER run on the same tag can kill a fresh retrigger — the exact '
            'rc1-recovery trap: a cancelled run sat on the tag, and the '
            'retrigger read it as "the build failed" within seconds.',
      );
      expect(
        forgeYaml.contains('T0='),
        isTrue,
        reason: 'The attempt anchor (T0) is gone from windows-ophalen.',
      );
      expect(
        RegExp(r'--max-time \d+').hasMatch(forgeYaml),
        isTrue,
        reason:
            'The polling curls run without --max-time: one blackholed '
            'connection hangs the 45-minute loop for hours.',
      );
    });

    test('the release notes offer it and say it does not update itself', () {
      // In the downloads table specifically, not merely somewhere in the
      // prose: the table is the part a reader actually scans for a file to
      // click. A mention further down does not put it in front of anyone.
      expect(
        RegExp(
          r'^\|[^|]*Windows[^|]*\|\s*`ocideck-windows-x64-setup-@VERSIE@\.exe`\s*\|',
          multiLine: true,
        ).hasMatch(releaseBody),
        isTrue,
        reason:
            'The installer has no row in the downloads table of '
            '.forgejo/release-body.md, so a release publishes a file nobody is '
            'told about.',
      );
      expect(
        releaseBody.contains('Neither checks for updates'),
        isTrue,
        reason:
            'The release notes offer an installer without saying it has no '
            'update channel — the one thing a reader will assume it has.',
      );
      expect(
        releaseBody.contains('SHA256SUMS'),
        isTrue,
        reason:
            'The notes must point at the manifest: with no code-signing '
            'certificate, that signature is the installer only provenance.',
      );
    });
  });
}
