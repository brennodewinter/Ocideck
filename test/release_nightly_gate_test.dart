@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards #2308: a fresh release must not walk past a nightly linux-gate that
/// already knows this main is broken (v0.6.14 ran phase 1 while the gate had
/// been red for four nights). The check is read-only: a missing, stale or
/// unfinished run is explicitly unknown — never silently green — and --resume
/// skips it entirely because a resumed release's content is already fixed.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  final autoScript = File(script).readAsStringSync();

  test('de poort draait vóór preflight en alleen read-only', () {
    // Voer de echte top-level aanroepvolgorde uit met tracerende grenzen. De
    // wachtwoordprompt mag binnen preflight verhuizen zolang de nightly gate
    // runtime vóór die hele stap blijft.
    final lines = autoScript.split('\n');
    final start = lines.indexWhere(
      (line) => line.contains('De twee prompts (de enige interactie)'),
    );
    final end = lines.indexWhere((line) => line.trim() == 'preflight', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final topLevel = lines.sublist(start + 1, end + 1).join('\n');
    final dir = Directory.systemTemp.createTempSync('ocideck-nightly-order-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
STEP=
MINISIGN_PW=old
read_token() { printf 'token\\n'; }
assert_no_pending_fixes() { printf 'blockers\\n'; }
assert_nightly_main_gate() { printf 'nightly\\n'; }
preflight() { printf 'preflight\\n'; }
$topLevel
''');
    final result = Process.runSync('bash', [harness.path]);
    final calls = (result.stdout as String).trim().split('\n');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(calls.indexOf('nightly'), lessThan(calls.indexOf('preflight')));

    // Geen neveneffect: de gate mag nooit zelf een run dispatchen.
    final gateCall = autoScript.indexOf('assert_nightly_main_gate\n');
    final body = autoScript.substring(
      autoScript.indexOf('assert_nightly_main_gate() {'),
      gateCall,
    );
    expect(body, isNot(contains('POST')));
    expect(body, isNot(contains('dispatches')));
  });

  String allFunctionDefinitions() {
    final lines = autoScript.split('\n');
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

  /// Draait de echte assert_nightly_main_gate met gemockte api/git.
  /// [runs] is "id|sha|status" per regel (nieuw→oud, sha '' = geen);
  /// [ancestors] zijn de sha's die git merge-base als voorvader van
  /// origin/main erkent.
  ProcessResult runGate({
    required List<String> runs,
    List<String> ancestors = const ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
    String resumeTag = '',
    bool apiFails = false,
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-nightly-gate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runsFile = File('${dir.path}/runs.tsv')
      ..writeAsStringSync('${runs.join('\n')}\n');
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
RESUME_TAG='$resumeTag'
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
git() {
  if [ "\$1" = rev-parse ]; then
    printf '%s\\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    return 0
  fi
  if [ "\$1" = merge-base ]; then
    case ' ${ancestors.join(' ')} ' in
      *" \$3 "*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 1
}
api() {
  ${apiFails ? 'return 22' : '''local method="\$1" path="\$2"
  case "\$path" in
    '/actions/runs?limit=50&workflow_id=linux-gate.yml')
      { printf '{"workflow_runs":['
        first=1
        while IFS='|' read -r rid rsha rstatus; do
          [ -n "\$rid" ] || continue
          [ "\$first" -eq 0 ] && printf ','
          first=0
          printf '{"id":%s,"prettyref":"main","status":"%s","html_url":"https://forge.invalid/r/%s"}' "\$rid" "\$rstatus" "\$rid"
        done < '${runsFile.path}'
        printf ']}\\n'
      }
      ;;
    '/actions/runs/'*'/jobs')
      printf '%s\\n' '[{"id":50,"name":"gate-linux","status":"failure","attempt":1}]'
      ;;
    '/actions/jobs/'*'/logs')
      printf '%s\\n' 'make check-no-coverage: FAILED test/foo_test.dart'
      ;;
    '/actions/runs/'*)
      rid="\${path#/actions/runs/}"
      while IFS='|' read -r r rsha rstatus; do
        if [ "\$r" = "\$rid" ]; then
          printf '{"commit_sha":"%s","status":"%s","html_url":"https://forge.invalid/r/%s"}\\n' "\$rsha" "\$rstatus" "\$rid"
          return 0
        fi
      done < '${runsFile.path}'
      printf '{}\\n'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac'''}
}
assert_nightly_main_gate
printf 'DOOR\\n'
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  test('een groene nachtrun op de tip laat de release door', () {
    final r = runGate(
      runs: ['9718|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|success'],
    );
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, 0, reason: output);
    expect(output, contains('DOOR'));
  });

  test(
    'een rode nachtrun stopt vóór elke mutatie, met run- en foutcontext',
    () {
      final r = runGate(
        runs: [
          '9718|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|failure',
          '9700|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|success',
        ],
      );
      final output = '${r.stdout}\n${r.stderr}';
      expect(r.exitCode, isNot(0), reason: output);
      expect(output, contains('https://forge.invalid/r/9718'));
      expect(output, contains('gate-linux'));
      expect(output, contains('FAILED test/foo_test.dart'));
    },
  );

  test('een run op een commit buiten main telt niet als goedkeuring', () {
    final r = runGate(
      runs: ['9718|cccccccccccccccccccccccccccccccccccccccc|success'],
    );
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('onbekend, niet groen'));
  });

  test('zonder linux-gate-run is de main-toestand onbekend, niet groen', () {
    final r = runGate(runs: []);
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('onbekend, niet groen'));
  });

  test('een nog lopende nachtrun is onbekend, niet groen', () {
    final r = runGate(
      runs: ['9718|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|running'],
    );
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('niet voltooid'));
  });

  test('een onbereikbare forge-API maakt de toestand onbekend, niet groen', () {
    final r = runGate(runs: [], apiFails: true);
    expect(r.exitCode, isNot(0), reason: '${r.stdout}\n${r.stderr}');
  });

  test('--resume slaat de nachtelijke main-poort over', () {
    // api die faalt bewijst dat er niets gelezen wordt: de inhoud van de
    // lopende release ligt al vast, een later rood main-run is irrelevant.
    final r = runGate(runs: [], resumeTag: 'v9.9.9', apiFails: true);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  }, skip: skipOnWindows);
}
