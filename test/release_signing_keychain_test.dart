@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('scripts/release_auto.sh').readAsStringSync();
  final start = script.indexOf('read_minisign_password() {');
  final end = script.indexOf('\n}\n', start);
  final function = script.substring(start, end + 3);

  ProcessResult run(int lookupStatus, {bool readWorks = true}) {
    final temp = Directory.systemTemp.createTempSync('signing-keychain-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final harness = File('${temp.path}/check.sh')
      ..writeAsStringSync('''
set -eu
MINISIGN_KEYCHAIN_SERVICE=ocideck-test
MINISIGN_PW=''
$function
section() { :; }
log() { printf '%s\\n' "\$1"; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
security() {
  case "\$*" in
    'find-generic-password -s ocideck-test') return $lookupStatus ;;
    'find-generic-password -s ocideck-test -w')
      ${readWorks ? "printf '%s\\n' test-password" : 'return 36'} ;;
    *) return 2 ;;
  esac
}
read_minisign_password </dev/null
printf 'loaded=%s\\n' "\$MINISIGN_PW"
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('bestaand sleutelhangeritem levert wachtwoord zonder prompt', () {
    final result = run(0);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('loaded=test-password'));
    expect(result.stdout, isNot(contains('minisign-wachtwoord:')));
  });

  test('ontbrekend item gebruikt interactieve terugval', () {
    final result = run(44);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('handmatige invoer'));
  });

  test('ontoegankelijk bestaand item faalt vroeg', () {
    final result = run(0, readWorks: false);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('kan niet worden gelezen'));
  });

  test('vergrendelde sleutelhanger valt niet terug op een prompt', () {
    final result = run(36);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('sleutelhangerstatus niet leesbaar'));
  });
}
