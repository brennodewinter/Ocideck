// Slaat Windows over: de test roept `bash scripts/update_homebrew_cask.sh` aan
// (awk/sed/sha256sum/mktemp), en de cask is macOS-only — op Windows draait dat
// script niet in productie en bash is er niet betrouwbaar. De GitHub Windows-
// runner gaf de drie cask-tests daarom consistent exit 1 (run 30942431938).
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De Homebrew-caskgenerator (`scripts/update_homebrew_cask.sh`).
///
/// Bewaakt de drie eigenschappen waar de cask op moet kunnen rekenen, en die
/// stil kapot kunnen gaan:
///   1. de gepinde hash komt uit de gepubliceerde `SHA256SUMS`, niet uit een
///      herberekening — de cask pint wat de release verstuurde;
///   2. de cask is **macOS-only** (Homebrew Cask kent geen Linux-casks) — geen
///      `on_linux`/`binary`, en geen `auto_updates` (dat zou `brew upgrade`
///      juist onderdrukken; OciDeck werkt zichzelf niet bij);
///   3. een prerelease-tag levert geen cask op.
void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('brew_cask');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  // Een SHA256SUMS-fixture in de vorm die `sha256sum ./*` schrijft (met "./").
  const macSha =
      '9e199155b109b195bf0a3c0a8303f181debf23c8cb06b7585a393dce461176e6';
  File writeSums(String version) {
    final f = File('${temp.path}/SHA256SUMS');
    f.writeAsStringSync(
      'aaaa  ./ocideck-$version.cdx.json\n'
      'bbbb  ./ocideck-linux-x64-$version.tar.gz\n'
      '$macSha  ./ocideck-macos-$version.zip\n'
      'cccc  ./ocideck-windows-x64-$version.zip\n',
    );
    return f;
  }

  ProcessResult run(String tag, String out, File sums) => Process.runSync(
    'bash',
    ['scripts/update_homebrew_cask.sh', tag, out],
    workingDirectory: repoRoot,
    environment: {
      'SHA256SUMS_FILE': sums.path,
      'TEMPLATE_FILE': '$repoRoot/homebrew/ocideck.rb.tmpl',
    },
  );

  test('vult een geldige macOS-cask met de hash uit SHA256SUMS', () {
    final out = '${temp.path}/ocideck.rb';
    final r = run('v0.3.0', out, writeSums('0.3.0'));
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final cask = File(out).readAsStringSync();
    expect(cask, contains('version "0.3.0"'));
    expect(cask, contains('sha256 "$macSha"'));
    expect(
      cask,
      contains(
        'url "https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/'
        'download/v0.3.0/ocideck-macos-0.3.0.zip"',
      ),
    );
    expect(cask, contains('app "OciDeck.app"'));
  });

  test('is macOS-only: geen Linux-arm, geen auto_updates', () {
    final out = '${temp.path}/ocideck.rb';
    expect(run('v1.4.0', out, writeSums('1.4.0')).exitCode, 0);

    final cask = File(out).readAsStringSync();
    expect(cask, isNot(contains('on_linux')));
    expect(cask, isNot(contains('binary ')));
    expect(cask, isNot(contains('auto_updates')));
  });

  test('een prerelease-tag levert geen cask op', () {
    final out = '${temp.path}/ocideck.rb';
    final r = run('v1.4.0-rc1', out, writeSums('1.4.0-rc1'));
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(File(out).existsSync(), isFalse);
  });

  test('faalt als de macOS-hash ontbreekt in SHA256SUMS', () {
    final sums = File('${temp.path}/SHA256SUMS')
      ..writeAsStringSync('bbbb  ./ocideck-linux-x64-2.0.0.tar.gz\n');
    final r = run('v2.0.0', '${temp.path}/ocideck.rb', sums);
    expect(r.exitCode, isNot(0));
  });
}
