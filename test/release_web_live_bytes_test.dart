import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final skip = Platform.isWindows ? 'Bash-releaseworkflow vereist Unix' : null;
  final script = File('scripts/release_auto.sh').readAsStringSync();
  final function = script.substring(
    script.indexOf('live_web_bundle_matches() {'),
    script.indexOf('\n}\n', script.indexOf('live_web_bundle_matches() {')) + 3,
  );

  Future<ProcessResult> check({
    bool tamper = false,
    bool missing = false,
  }) async {
    final dir = Directory.systemTemp.createTempSync('ocideck-live-bytes-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = <String, String>{
      'version.json': '{"version":"9.9.9"}',
      'main.dart.js': 'verified release bytes',
      'assets/with space.txt': 'quoted URL',
    };
    final manifest = files.entries
        .map(
          (entry) =>
              '${sha256.convert(utf8.encode(entry.value))}  ${entry.key}',
        )
        .join('\n');
    File('${dir.path}/SHA256SUMS').writeAsStringSync('$manifest\n');
    for (final entry in files.entries) {
      File('${dir.path}/${entry.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    if (tamper) {
      File('${dir.path}/main.dart.js').writeAsStringSync('altered bytes');
    }
    if (missing) File('${dir.path}/main.dart.js').deleteSync();
    final server = await Process.start('python3', [
      '-u',
      '-c',
      // Reverse-DNS van loopback kan langer duren dan de hele lokale byteproef.
      'import http.server,socket; '
          'socket.getfqdn=lambda *_: "localhost"; '
          'server=http.server.ThreadingHTTPServer(("127.0.0.1",0),http.server.SimpleHTTPRequestHandler); '
          'print(server.server_port,flush=True); server.serve_forever()',
    ], workingDirectory: dir.path);
    final errors = server.stderr.drain<void>();
    addTearDown(() async {
      server.kill();
      await server.exitCode;
      await errors;
    });
    final port = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -Eeuo pipefail
DEPLOY_URL=http://127.0.0.1:$port
$function
live_web_bundle_matches '${dir.path}'
''');
    return Process.run('bash', [harness.path]);
  }

  test('live bestanden met exact dezelfde hashes worden aanvaard', () async {
    final result = await check();
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: skip);

  test(
    'gewijzigde bytes met ongewijzigde versie en manifest worden geweigerd',
    () async {
      final result = await check(tamper: true);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('publieke webbestanden wijken af'));
    },
    skip: skip,
  );

  test('ontbrekend publiek bestand wordt geweigerd', () async {
    final result = await check(missing: true);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('publieke webbestanden wijken af'));
  }, skip: skip);
}
