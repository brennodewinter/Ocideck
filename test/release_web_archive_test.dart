import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final skip = Platform.isWindows ? 'Bash-releaseworkflow vereist Unix' : null;
  final source = File('scripts/release_auto.sh').readAsStringSync().split('\n');
  final functions = <String>[];
  for (var i = 0; i < source.length; i++) {
    if (!RegExp(r'^\w+\(\)\s*\{').hasMatch(source[i])) continue;
    for (; i < source.length; i++) {
      functions.add(source[i]);
      if (source[i] == '}') break;
    }
  }

  ProcessResult prepare(
    String fixture, {
    bool validHash = true,
    bool missingAsset = false,
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-web-archive-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final generator = Process.runSync('python3', [
      '-c',
      r'''
import hashlib, io, json, pathlib, sys, tarfile
root = pathlib.Path(sys.argv[1]); kind = sys.argv[2]
with tarfile.open(root/'fixture.tar.gz', 'w:gz') as archive:
    for name, data in [('version.json', (b'{"version":"9.9.8"}' if kind == 'wrong-version' else b'{"version":"9.9.9"}')), ('index.html', b'release'), ('SHA256SUMS', b'inner-manifest')]:
        member = tarfile.TarInfo(name); member.size = len(data)
        archive.addfile(member, io.BytesIO(data))
    if kind in ('traversal', 'symlink', 'special'):
        member = tarfile.TarInfo('../escaped' if kind == 'traversal' else 'unsafe')
        if kind == 'symlink': member.type = tarfile.SYMTYPE; member.linkname = '/tmp/escaped'
        if kind == 'special': member.type = tarfile.FIFOTYPE
        archive.addfile(member)
sha = hashlib.sha256((root/'fixture.tar.gz').read_bytes()).hexdigest()
(root/'manifest').write_text(sha+'  ocideck-web-9.9.9.tar.gz\n')
''',
      dir.path,
      fixture,
    ]);
    expect(generator.exitCode, 0, reason: generator.stderr.toString());
    if (!validHash) {
      File(
        '${dir.path}/manifest',
      ).writeAsStringSync('${'0' * 64}  ocideck-web-9.9.9.tar.gz\n');
    }
    Directory('${dir.path}/bundle').createSync();
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -Eeuo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
${functions.join('\n')}
log() { :; }
verify_release_manifest() { return 0; }
api() {
  case "\$2" in
    /releases/tags/*) printf '{"id":41}' ;;
    /releases/41/assets) printf '%s' '[{"name":"SHA256SUMS","browser_download_url":"fixture:manifest"}${missingAsset ? '' : ',{"name":"ocideck-web-9.9.9.tar.gz","browser_download_url":"fixture:archive"}'}]' ;;
    *) return 1 ;;
  esac
}
download_release_asset() {
  case "\$1" in
    fixture:manifest) cp '${dir.path}/manifest' "\$2" ;;
    fixture:archive) cp '${dir.path}/fixture.tar.gz' "\$2" ;;
    *) return 1 ;;
  esac
}
prepare_release_web_bundle '${dir.path}/bundle'
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('releasearchief met correct buitenmanifest wordt uitgepakt', () {
    final result = prepare('valid');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: skip);

  test('ontbrekend webasset blokkeert deployment', () {
    expect(prepare('valid', missingAsset: true).exitCode, isNot(0));
  }, skip: skip);

  test('verkeerde archiefhash blokkeert deployment', () {
    final result = prepare('valid', validHash: false);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('webbundel wijkt af van SHA256SUMS'));
  }, skip: skip);

  for (final fixture in ['traversal', 'symlink', 'special', 'wrong-version']) {
    test('releasearchief weigert $fixture', () {
      final result = prepare(fixture);
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains(
          fixture == 'wrong-version'
              ? 'webbundel bevat een andere versie'
              : 'onveilig pad of bestandstype',
        ),
      );
    }, skip: skip);
  }
}
