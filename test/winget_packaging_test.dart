// The generator uses bash/awk/sed and exists for the Windows package catalog,
// so Windows validates the generated manifest itself rather than this shell test.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the WinGet manifest generator and the sovereignty boundary around it:
/// WinGet indexes the exact installer on the canonical forge, while direct
/// downloads remain available independently of Microsoft's catalog.
void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('winget_manifest');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  const installerSha =
      '3b60d7bc4507f72398b1574149ce7b9224ad31d49843f9f906e78029b8718f88';

  File writeSums(String version, {bool includeInstaller = true}) {
    final file = File('${temp.path}/SHA256SUMS');
    file.writeAsStringSync(
      'aaaa  ./ocideck-$version.cdx.json\n'
      '${includeInstaller ? '$installerSha  ./ocideck-windows-x64-setup-$version.exe\n' : ''}'
      'bbbb  ./ocideck-windows-x64-$version.zip\n',
    );
    return file;
  }

  ProcessResult run(String tag, Directory out, File sums) => Process.runSync(
    'bash',
    ['scripts/update_winget_manifest.sh', tag, out.path],
    workingDirectory: repoRoot,
    environment: {'SHA256SUMS_FILE': sums.path},
  );

  Directory versionDir(Directory out, String version) =>
      Directory('${out.path}/manifests/l/LibreKAT/OciDeck/$version');

  test('writes the three-file community manifest at the required path', () {
    final out = Directory('${temp.path}/out');
    final result = run('v0.6.3', out, writeSums('0.6.3'));
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final dir = versionDir(out, '0.6.3');
    expect(dir.listSync().map((entry) => entry.path.split('/').last).toSet(), {
      'LibreKAT.OciDeck.yaml',
      'LibreKAT.OciDeck.installer.yaml',
      'LibreKAT.OciDeck.locale.en-US.yaml',
    });
  });

  test('pins the canonical Forgejo installer and its published hash', () {
    final out = Directory('${temp.path}/out');
    expect(run('0.6.3', out, writeSums('0.6.3')).exitCode, 0);

    final installer = File(
      '${versionDir(out, '0.6.3').path}/LibreKAT.OciDeck.installer.yaml',
    ).readAsStringSync();
    expect(installer, contains('PackageIdentifier: LibreKAT.OciDeck'));
    expect(installer, contains("PackageVersion: '0.6.3'"));
    expect(installer, contains('InstallerType: inno'));
    expect(installer, contains('Architecture: x64'));
    expect(installer, contains('ElevationRequirement: elevationRequired'));
    expect(
      installer,
      contains(
        'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/'
        'download/v0.6.3/ocideck-windows-x64-setup-0.6.3.exe',
      ),
    );
    expect(installer, contains(installerSha.toUpperCase()));
    expect(installer, isNot(contains('github.com/brennodewinter')));
  });

  test('keeps the fixed Inno upgrade identity in the manifest', () {
    final out = Directory('${temp.path}/out');
    expect(run('v1.2.3', out, writeSums('1.2.3')).exitCode, 0);
    final installer = File(
      '${versionDir(out, '1.2.3').path}/LibreKAT.OciDeck.installer.yaml',
    ).readAsStringSync();
    expect(
      RegExp(
        r'\{5AEB475C-9E67-475B-BB99-F52816B739C8\}_is1',
      ).allMatches(installer),
      hasLength(2),
    );
    expect(installer, contains('UpgradeBehavior: install'));
  });

  test('does not publish prereleases', () {
    final out = Directory('${temp.path}/out');
    final result = run('v0.6.4-rc1', out, writeSums('0.6.4-rc1'));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(out.existsSync(), isFalse);
  });

  test('fails closed when the release does not list the installer', () {
    final out = Directory('${temp.path}/out');
    final result = run(
      'v0.6.3',
      out,
      writeSums('0.6.3', includeInstaller: false),
    );
    expect(result.exitCode, isNot(0));
    expect(out.existsSync(), isFalse);
  });
}
