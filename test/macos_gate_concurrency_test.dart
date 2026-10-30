import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// De releasekandidaat toetst goldens vóór de tag. De losse macOS-poort is
/// nog het post-merge vangnet voor gewone main-wijzigingen.
void main() {
  final workflow = File('.forgejo/workflows/macos-gate.yml');
  final yaml = loadYaml(workflow.readAsStringSync());
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  test('goldens draaien op de kandidaat vóór de tag', () {
    final on = yaml['on'] as YamlMap;
    final push = on['push'] as YamlMap;
    expect(push['tags'], isNull);
    final branches = (push['branches'] as YamlList).map((e) => '$e').toList();
    expect(branches, contains('main'), reason: 'de post-merge vangnet blijft');
    final release = File('.forgejo/workflows/release.yml').readAsStringSync();
    expect(release, contains('make test-golden'));
  });

  test('de concurrencygroep volgt de main-ref', () {
    final concurrency = yaml['concurrency'] as YamlMap;
    final group = '${concurrency['group']}';
    // Een nieuwe main-push mag een oude vangnetrun annuleren.
    expect(
      group,
      contains('github.ref'),
      reason: 'de groep volgt de ref van de getoetste main-versie',
    );
    expect(group, isNot(contains('head_commit')));
    expect(
      concurrency['cancel-in-progress'],
      isTrue,
      reason: 'binnen main mag de nieuwste vangnetrun de oude vervangen',
    );
  });

  group('macos_gate_tag_status (release_auto)', () {
    const script = 'scripts/release_auto.sh';

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
      final dir = Directory.systemTemp.createTempSync('ocideck-mgate-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final harness = File('${dir.path}/harness.sh');
      harness.writeAsStringSync('''
set -uo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
STEP=test
${allFunctionDefinitions()}
log() { printf '%s\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
$body
''');
      return Process.runSync('bash', [
        harness.path,
      ], workingDirectory: Directory.current.path);
    }

    test('volgt de tagrun, niet de geannuleerde main-run', () {
      // Het v0.6.14-incident: run 5477 op refs/heads/main (de mergecommit die
      // de tag zou dragen) werd geannuleerd door een latere merge. De helper
      // moet de run op de tagref volgen — die in zijn eigen groep staat.
      final result = runHarness(r'''
api() {
  case "$1 $2" in
    'GET /actions/runs?limit=50&page=1&workflow_id=macos-gate.yml')
      printf '%s\n' '{"workflow_runs":[
        {"id":5477,"prettyref":"main","workflow_id":"macos-gate.yml","status":"cancelled"},
        {"id":5480,"prettyref":"main","workflow_id":"macos-gate.yml","status":"success"},
        {"id":5490,"prettyref":"v9.9.9","workflow_id":"macos-gate.yml","status":"running"}
      ]}'
      ;;
    *) printf '%s\n' '{}' ;;
  esac
}
macos_gate_tag_status
''');
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(
        output,
        contains('running|5490'),
        reason: 'alleen de run op de tagref is "de poort voor de tagcommit"',
      );
      expect(output, isNot(contains('5477')));
      expect(output, isNot(contains('5480')));
    }, skip: skipOnWindows);

    test('volgt een gerichte herstart: dezelfde run, nieuwe status', () {
      // Een herstart van de tagrun komt onder dezelfde run-id terug met een
      // bijgewerkte status — de helper leest die gewoon mee.
      final result = runHarness(r'''
api() {
  case "$1 $2" in
    'GET /actions/runs?limit=50&page=1&workflow_id=macos-gate.yml')
      printf '%s\n' '{"workflow_runs":[
        {"id":5490,"prettyref":"v9.9.9","workflow_id":"macos-gate.yml","status":"success"}
      ]}'
      ;;
    *) printf '%s\n' '{}' ;;
  esac
}
macos_gate_tag_status
''');
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('success|5490'));
    }, skip: skipOnWindows);

    test('een onleesbare API faalt hoorbaar, niet stil leeg', () {
      final result = runHarness(r'''
api() { return 1; }
macos_gate_tag_status
''');
      expect(result.exitCode, isNot(0));
    }, skip: skipOnWindows);
  });
}
