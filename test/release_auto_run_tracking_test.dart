import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressies voor #2294: de releaseketen volgt Forgejo-workflowRUNS,
/// niet runner-taken. Een run die nog in de wachtrij staat en dus geen
/// /actions/tasks-entry heeft is bestaand en actief; een snapshot mag nooit
/// jobs uit verschillende pogingen samenvoegen.
///
/// De echte bashfuncties draaien in een hermetisch harnas; alleen de
/// Forgejo-grens (api), de wachttijd en de registercontrole zijn gemockt.
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
    final dir = Directory.systemTemp.createTempSync('ocideck-run-tracking-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
STEP=test
snap=
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
$body
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  test('een queued run zonder runner-taak telt als bestaande actieve run', () {
    // De v0.6.14-fout: de dispatch maakte run 9655 wel aan, maar zolang er
    // nog geen runner-taak was bleef /actions/tasks leeg en stopte de keten
    // ten onrechte. Hier staat de run eerst zonder job, daarna running en
    // success; de registercontrole bevestigt de tag.
    final result = runHarness(r'''
BRANCH=release/v9.9.9
COUNT_FILE=$(mktemp)
api() {
  case "$1 $2" in
    'POST /actions/workflows/ci-image-scans.yml/dispatches')
      printf '%s\n' '{"id":777,"run_number":42,"jobs":["build-publish"]}'
      ;;
    'GET /actions/runs/777/jobs')
      n=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
      printf '%s' "$n" >"$COUNT_FILE"
      case "$n" in
        1) printf '%s\n' '[]' ;;
        2) printf '%s\n' '[{"name":"build-publish","status":"running","id":9,"attempt":1}]' ;;
        *) printf '%s\n' '[{"name":"build-publish","status":"success","id":9,"attempt":1}]' ;;
      esac
      ;;
    *) printf '%s\n' '{}' ;;
  esac
}
scan_image_available() { return 0; }
publish_scans_image gl9-th9-sg9
echo KLAAR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('run 777'));
    expect(
      output,
      isNot(contains('geen ci-image-scans-run aangemaakt')),
      reason: 'een queued run zonder job is wachttoestand, geen afwezigheid',
    );
    expect(output, contains('KLAAR'));
  }, skip: skipOnWindows);

  test('zonder return_run_info resolft de dispatch de run via de runlijst', () {
    // Een oudere Forgejo antwoordt 204 met een lege body op de dispatch;
    // de nieuwste ci-image-scans-run op de ref is dan de zojuist gestarte.
    final result = runHarness(r'''
BRANCH=release/v9.9.9
api() {
  case "$1 $2" in
    'POST /actions/workflows/ci-image-scans.yml/dispatches')
      printf '' ;;  # 204: geen run-info terug
    'GET /actions/runs?limit=50&workflow_id=ci-image-scans.yml')
      printf '%s\n' '{"workflow_runs":[{"id":778,"prettyref":"release/v9.9.9","workflow_id":"ci-image-scans.yml","status":"running"}]}'
      ;;
    'GET /actions/runs/778/jobs')
      printf '%s\n' '[{"name":"build-publish","status":"success","id":9,"attempt":1}]'
      ;;
    *) printf '%s\n' '{}' ;;
  esac
}
scan_image_available() { return 0; }
publish_scans_image gl9-th9-sg9
echo KLAAR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('KLAAR'));
  }, skip: skipOnWindows);

  test('een oude complete poging smelt nooit samen met een nieuwe run', () {
    // Run 100 is compleet groen; run 200 is de actuele poging en nog maar
    // halverwege. De snapshot mag uitsluitend jobs van run 200 bevatten en
    // fase 3 mag niet starten.
    final result = runHarness(r'''
BRANCH=release/v9.9.9
api() {
  case "$1 $2" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\n' '{"workflow_runs":[
        {"id":100,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"success"},
        {"id":200,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"running"}
      ]}'
      ;;
    'GET /actions/runs/200/jobs')
      printf '%s\n' '[{"name":"Poort (vóór het bouwen)","status":"success","id":1,"attempt":1},{"name":"Linux bouwen","status":"running","id":2,"attempt":1}]'
      ;;
    'GET /actions/runs/100/jobs')
      printf '%s\n' '[{"name":"Poort (vóór het bouwen)","status":"success","id":10,"attempt":1},{"name":"Website-downloads bijwerken","status":"success","id":11,"attempt":1}]'
      ;;
    *) printf '%s\n' '{}' ;;
  esac
}
release_ci_snapshot > /tmp/ocideck-snap-out.txt
assert_release_ci_terminal
echo DOOR
''');
    final snap = File('/tmp/ocideck-snap-out.txt').readAsStringSync();
    addTearDown(() => File('/tmp/ocideck-snap-out.txt').deleteSync());
    expect(snap, contains('running|Linux bouwen'));
    expect(
      snap,
      isNot(contains('Website-downloads bijwerken')),
      reason:
          'de oude complete run mag geen jobs aan de nieuwe snapshot leveren',
    );
    expect(result.exitCode, isNot(0), reason: 'fase 3 mag niet starten');
    expect(
      result.stderr,
      contains('nog actief'),
      reason: 'een gedeeltelijke run is actief, niet compleet',
    );
  }, skip: skipOnWindows);

  test('een onleesbare Forgejo-API is onbekend, niet afwezig', () {
    final result = runHarness(r'''
BRANCH=release/v9.9.9
api() { return 1; }
assert_release_ci_terminal
echo DOOR
''');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('onbekend is niet afwezig'));
    expect(
      result.stderr,
      isNot(contains('geen release-run')),
      reason: 'een API-fout mag niet als afwezigheid worden gelezen',
    );
  }, skip: skipOnWindows);
}
