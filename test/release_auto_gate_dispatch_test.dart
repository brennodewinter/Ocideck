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
  if [ "\$method \$path" = 'GET /actions/runs?limit=50' ]; then
    printf '%s\n' '{"workflow_runs":[]}'
    return 0
  fi
  if [ "\$method" = POST ]; then
    printf '%s %s %s\n' "\$method" "\$path" "\${*:3}" >>"\$TRACE"
    printf '%s\n' '{"id":7,"run_number":42,"jobs":["gate"]}'
    return 0
  fi
  printf '%s\n' '{}'
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
  if [ "$method $path" = 'GET /actions/runs?limit=50' ]; then
    printf '%s\n' '{"workflow_runs":[
      {"id":1,"workflow_id":"static-gate.yml","title":"static-gate","status":"success","commit_sha":"abc123"},
      {"id":2,"workflow_id":"scans.yml","title":"scans","status":"success","commit_sha":"abc123"},
      {"id":3,"workflow_id":"linux-gate.yml","title":"linux-gate","status":"success","commit_sha":"abc123"}
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

  test('nachtelijke main-poort accepteert geen groene voorouder', () {
    final result = runHarness(r'''
RESUME_TAG=
git() {
  case "$*" in
    'rev-parse --verify origin/main') printf '%s\n' 'tip-sha' ;;
    'merge-base --is-ancestor old-sha tip-sha') return 0 ;;
    *) return 1 ;;
  esac
}
api() {
  case "$2" in
    '/actions/runs?limit=50&workflow_id=linux-gate.yml')
      printf '%s\n' '{"workflow_runs":[{"id":7,"prettyref":"main"}]}' ;;
    '/actions/runs/7')
      printf '%s\n' '{"commit_sha":"old-sha","status":"success","html_url":"https://forge.invalid/7"}' ;;
    *) printf '%s\n' '{}' ;;
  esac
}
die() { printf 'DIE: %s\n' "$1" >&2; exit 99; }
assert_nightly_main_gate
''');

    expect(result.exitCode, 99, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('main-tip'));
  }, skip: skipOnWindows);

  test('wait_gate houdt een wall-clockdeadline aan bij een trage poll', () {
    final polls = File(
      '${Directory.systemTemp.path}/ocideck-gate-deadline-$pid.log',
    );
    addTearDown(() {
      if (polls.existsSync()) polls.deleteSync();
    });
    final stopwatch = Stopwatch()..start();
    final result = runHarness('''
POLLS=${polls.path}
GATE_TIMEOUT_SECONDS=2
GATE_TIMEOUT_MIN=0
ensure_gate_tasks() { :; }
gate_task_snapshot() {
  printf 'poll\\n' >>"\$POLLS"
  command sleep 3
  printf '%s\n' 'static-gate.yml|running|static|1'
}
die() { printf 'DIE: %s\n' "\$1" >&2; exit 99; }
wait_gate abc123 2194
''');
    stopwatch.stop();

    expect(result.exitCode, 99, reason: '${result.stdout}\n${result.stderr}');
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(milliseconds: 4500)),
      reason:
          'na de ene begrensde poll mag geen tweede poll meer starten; '
          'dit duurde ${stopwatch.elapsed}.',
    );
    expect(
      stopwatch.elapsed,
      greaterThan(const Duration(milliseconds: 2500)),
      reason:
          'de eerste poll mag zijn eigen begrensde duur afmaken; een directe '
          'terugkeer betekent dat GATE_TIMEOUT_SECONDS is genegeerd.',
    );
    expect(polls.readAsLinesSync(), ['poll']);
  }, skip: skipOnWindows);

  test('scan_image_available begrenst beide curl-aanroepen', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-scan-image-curl-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final result = runHarness('''
TRACE=${trace.path}
curl() {
  printf '%s\n' "\$*" >>"\$TRACE"
  case "\$*" in
    *'/v2/token'*) printf '%s\n' '{"token":"test-token"}' ;;
    *'/manifests/'*) printf '200' ;;
    *) return 22 ;;
  esac
}
scan_image_available test-tag
''');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final calls = trace.readAsLinesSync();
    expect(calls, hasLength(2));
    for (final call in calls) {
      expect(call, contains('--connect-timeout'), reason: call);
      expect(call, contains('--max-time'), reason: call);
    }
  }, skip: skipOnWindows);
}
