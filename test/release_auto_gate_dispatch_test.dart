import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressietoets voor de v0.6.11-release die 75 minuten wachtte op
/// statuscontexten die niet meer konden ontstaan.
///
/// `static-gate`, `scans` en `linux-gate` zijn bewust alleen via
/// `workflow_dispatch` startbaar. De releaseketen moet ze daarom zelf starten
/// en hun Forgejo-taken volgen; de gecombineerde commitstatus blijft leeg.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  String allFunctionDefinitions() {
    final lines = File(script).readAsStringSync().split('\n');
    final out = <String>[];
    final open = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{');
    for (var i = 0; i < lines.length; i++) {
      if (!open.hasMatch(lines[i])) continue;
      for (; i < lines.length; i++) {
        out.add(lines[i]);
        if (RegExp(r'^\}\s*$').hasMatch(lines[i])) break;
      }
    }
    return out.join('\n');
  }

  ProcessResult runHarness(String body) {
    final dir = Directory.systemTemp.createTempSync('ocideck-release-gate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
TAG=v9.9.9
BRANCH=release/v9.9.9
GATE_TIMEOUT_MIN=1
STEP=test
${allFunctionDefinitions()}
log() { printf '%s\n' "\$1"; }
die() { printf 'DIE: %s\n' "\$1" >&2; return 99; }
sleep() { :; }
$body
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('start de drie handmatige poorten wanneer nog geen taak bestaat', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-gate-dispatch-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final result = runHarness('''
TRACE=${trace.path}
api() {
  local method="\$1" path="\$2"
  if [ "\$method \$path" = 'GET /actions/tasks?limit=100' ]; then
    printf '%s\n' '{"workflow_runs":[]}'
    return 0
  fi
  printf '%s %s %s\n' "\$method" "\$path" "\${*:3}" >>"\$TRACE"
}
ensure_gate_tasks abc123 2194
''');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final calls = trace.existsSync() ? trace.readAsStringSync() : '';
    for (final workflow in ['static-gate.yml', 'scans.yml', 'linux-gate.yml']) {
      expect(
        calls,
        contains('/actions/workflows/$workflow/dispatches'),
        reason: '$workflow moet door de releaseketen worden gestart.\n$calls',
      );
    }
  }, skip: skipOnWindows);

  test('groene handmatige taken voltooien de poort zonder commitstatus', () {
    final result = runHarness(r'''
api() {
  local method="$1" path="$2"
  if [ "$method $path" = 'GET /actions/tasks?limit=100' ]; then
    printf '%s\n' '{"workflow_runs":[
      {"id":1,"workflow_id":"static-gate.yml","name":"static-gate","status":"success","head_sha":"abc123"},
      {"id":2,"workflow_id":"scans.yml","name":"scans","status":"success","head_sha":"abc123"},
      {"id":3,"workflow_id":"linux-gate.yml","name":"linux-gate","status":"success","head_sha":"abc123"}
    ]}'
    return 0
  fi
  printf '%s\n' '{}'
}
wait_gate abc123 2194
''');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Poort groen.'));
    expect(result.stderr, isNot(contains('poort werd niet groen')));
  }, skip: skipOnWindows);
}
