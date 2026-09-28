@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/release_manifest_test_support.dart';

void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('aur_pkgbuild');
    writeFakeMinisign(temp);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  const linuxSha =
      'd2c7f2c3854f69c81ea1b57c23f5ffdcdd306881947de49983b76ae2c426c5bf';

  File writeSums(String version) =>
      File('${temp.path}/SHA256SUMS')
        ..writeAsStringSync('$linuxSha  ./ocideck-linux-x64-$version.tar.gz\n');

  File copyPkgbuild() =>
      File('${temp.path}/PKGBUILD')
        ..writeAsStringSync(File('packaging/aur/PKGBUILD').readAsStringSync());

  ProcessResult run(String tag, File pkgbuild, File sums) => Process.runSync(
    'bash',
    ['scripts/update_aur_pkgbuild.sh', tag, pkgbuild.path],
    workingDirectory: repoRoot,
    environment: {
      'SHA256SUMS_FILE': sums.path,
      'PATH': '${temp.path}:${Platform.environment['PATH']}',
    },
  );

  test('updates pkgver and hash from a verified local release manifest', () {
    final sums = writeSums('1.2.3');
    signTestManifest(sums);
    final pkgbuild = copyPkgbuild();

    final result = run('v1.2.3', pkgbuild, sums);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(pkgbuild.readAsStringSync(), contains('pkgver=1.2.3'));
    expect(pkgbuild.readAsStringSync(), contains("sha256sums=('$linuxSha')"));
  });

  test('accepts a version without v but keeps the canonical release URL', () {
    final sums = writeSums('1.2.3');
    signTestManifest(sums);
    final pkgbuild = copyPkgbuild();

    final result = run('1.2.3', pkgbuild, sums);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(pkgbuild.readAsStringSync(), contains('pkgver=1.2.3'));
  });

  test('rejects an invalid stable version without changing PKGBUILD', () {
    final pkgbuild = copyPkgbuild();
    final before = pkgbuild.readAsBytesSync();

    final result = run('not_a_version', pkgbuild, writeSums('not_a_version'));

    expect(result.exitCode, isNot(0));
    expect(pkgbuild.readAsBytesSync(), before);
  });

  test('refuses an unsigned local manifest without changing PKGBUILD', () {
    final sums = writeSums('1.2.3');
    final pkgbuild = copyPkgbuild();
    final before = pkgbuild.readAsBytesSync();

    final result = run('v1.2.3', pkgbuild, sums);

    expect(result.exitCode, isNot(0));
    expect(pkgbuild.readAsBytesSync(), before);
  });

  test('refuses a manifest changed after it was signed', () {
    final sums = writeSums('1.2.3');
    signTestManifest(sums);
    sums.writeAsStringSync('${'0' * 64}  ./ocideck-linux-x64-1.2.3.tar.gz\n');
    final pkgbuild = copyPkgbuild();
    final before = pkgbuild.readAsBytesSync();

    final result = run('v1.2.3', pkgbuild, sums);

    expect(result.exitCode, isNot(0));
    expect(pkgbuild.readAsBytesSync(), before);
  });

  test('downloads and verifies the public manifest pair', () {
    final sums = writeSums('1.2.3');
    signTestManifest(sums);
    writeFakeCurl(temp);
    final pkgbuild = copyPkgbuild();

    final result = Process.runSync(
      'bash',
      ['scripts/update_aur_pkgbuild.sh', 'v1.2.3', pkgbuild.path],
      workingDirectory: repoRoot,
      environment: {
        'PATH': '${temp.path}:${Platform.environment['PATH']}',
        'FAKE_RELEASE_DIR': temp.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(pkgbuild.readAsStringSync(), contains('pkgver=1.2.3'));
  });
}
