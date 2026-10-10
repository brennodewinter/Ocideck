@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards #2308: a fresh release must not walk past a linux-gate that has not
/// proved the current main tip. A missing run is started here and followed to
/// completion; failed or unknown is never silently green. --resume skips the
/// check because a resumed release's content is already fixed.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  final autoScript = File(script).readAsStringSync();

  test('de poort draait vóór preflight', () {
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
  });

  test('de ververste main-tip wordt vóór de fase-1-checkout herkeurd', () {
    final phaseOne = autoScript.indexOf('section "Fase 1 — voorbereiden"');
    final fetch = autoScript.indexOf('git fetch origin --quiet', phaseOne);
    final checkout = autoScript.indexOf(
      'git checkout -b "\$BRANCH" origin/main --quiet',
      fetch,
    );
    expect(phaseOne, isNonNegative);
    expect(fetch, greaterThan(phaseOne));
    expect(checkout, greaterThan(fetch));
    expect(
      autoScript.substring(fetch, checkout),
      contains('assert_nightly_main_gate'),
    );
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
    String dispatchedStatus = 'success',
    bool runningBecomesSuccess = false,
    String dispatchResponse = '{"id":9800}',
    String listWorkflowId = 'linux-gate.yml',
    bool wrongListSchema = false,
    bool lockHeld = false,
    File? trace,
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-nightly-gate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runsFile = File('${dir.path}/runs.tsv')
      ..writeAsStringSync('${runs.join('\n')}\n');
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
RESUME_TAG='$resumeTag'
GATE_TIMEOUT_MIN=1
GATE_TIMEOUT_SECONDS=2
MAIN_GATE_LOCK_DIR='${dir.path}/main-gate.lock'
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
  [ -z '${trace?.path ?? ''}' ] || printf '%s %s\\n' "\$method" "\$path" >> '${trace?.path ?? '/dev/null'}'
  case "\$path" in
    '/actions/runs?limit=50&workflow_id=linux-gate.yml')
      if [ '${wrongListSchema ? '1' : '0'}' -eq 1 ]; then
        printf '%s\n' '{"message":"unexpected response"}'
        return 0
      fi
      { printf '{"workflow_runs":['
        first=1
        while IFS='|' read -r rid rsha rstatus; do
          [ -n "\$rid" ] || continue
          [ "\$first" -eq 0 ] && printf ','
          first=0
          printf '{"id":%s,"workflow_id":"${listWorkflowId}","prettyref":"main","status":"%s","html_url":"https://forge.invalid/r/%s"}' "\$rid" "\$rstatus" "\$rid"
        done < '${runsFile.path}'
        if [ -f '${dir.path}/dispatched' ]; then
          [ "\$first" -eq 0 ] && printf ','
          printf '{"id":9800,"workflow_id":"linux-gate.yml","prettyref":"main","status":"${dispatchedStatus}","html_url":"https://forge.invalid/r/9800"}'
        fi
        printf ']}\\n'
      }
      ;;
    '/actions/workflows/linux-gate.yml/dispatches')
      [ "\$method" = POST ] || return 22
      : > '${dir.path}/dispatched'
      printf '%s\\n' '${dispatchResponse}'
      ;;
    '/actions/runs/'*'/jobs')
      printf '%s\\n' '[{"id":50,"name":"gate-linux","status":"failure","attempt":1}]'
      ;;
    '/actions/jobs/'*'/logs')
      printf '%s\\n' 'make check-no-coverage: FAILED test/foo_test.dart'
      ;;
    '/actions/runs/'*)
      rid="\${path#/actions/runs/}"
      if [ "\$rid" = 9800 ] && [ -f '${dir.path}/dispatched' ]; then
        printf '{"commit_sha":"%s","status":"%s","html_url":"https://forge.invalid/r/9800"}\\n' \\
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' '${dispatchedStatus}'
        return 0
      fi
      while IFS='|' read -r r rsha rstatus; do
        if [ "\$r" = "\$rid" ]; then
          if [ '${runningBecomesSuccess ? '1' : '0'}' -eq 1 ] && [ "\$rstatus" = running ]; then
            if [ -f '${dir.path}/seen-running' ]; then
              rstatus=success
            else
              : > '${dir.path}/seen-running'
            fi
          fi
          printf '{"commit_sha":"%s","status":"%s","html_url":"https://forge.invalid/r/%s"}\\n' "\$rsha" "\$rstatus" "\$rid"
          return 0
        fi
      done < '${runsFile.path}'
      printf '{}\\n'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac'''}
}
${lockHeld ? '''mkdir -p "\$MAIN_GATE_LOCK_DIR"
printf '%s\n' "\$PPID" > "\$MAIN_GATE_LOCK_DIR/pid"''' : ''}
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

  test('zonder groene tiprun start en volgt de release zelf linux-gate', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-nightly-dispatch-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final r = runGate(runs: [], trace: trace);
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, 0, reason: output);
    expect(output, contains('DOOR'));
    expect(
      trace.readAsStringSync(),
      contains('POST /actions/workflows/linux-gate.yml/dispatches'),
    );
    expect(trace.readAsStringSync(), contains('GET /actions/runs/9800'));
  });

  test(
    'een lege dispatchbevestiging wordt via de aangemaakte run hersteld',
    () {
      final r = runGate(runs: [], dispatchResponse: '');
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    },
  );

  test('een andere workflow op dezelfde SHA telt niet als linux-gate', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-nightly-workflow-id-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final r = runGate(
      runs: ['9718|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|success'],
      listWorkflowId: 'other.yml',
      trace: trace,
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(
      trace.readAsStringSync(),
      contains('POST /actions/workflows/linux-gate.yml/dispatches'),
    );
  });

  test('een onjuist lijstschema veroorzaakt geen dispatch', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-nightly-schema-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final r = runGate(runs: [], wrongListSchema: true, trace: trace);
    expect(r.exitCode, isNot(0), reason: '${r.stdout}\n${r.stderr}');
    expect(trace.readAsStringSync(), isNot(contains('POST ')));
  });

  test('een tweede releaseproces kan niet dubbel dispatchen', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-nightly-lock-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final r = runGate(runs: [], lockHeld: true, trace: trace);
    expect(r.exitCode, isNot(0), reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}\n${r.stderr}', contains('andere release'));
    expect(
      trace.existsSync() ? trace.readAsStringSync() : '',
      isNot(contains('POST ')),
    );
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

  test('een lopende tiprun wordt gevolgd zonder dubbele dispatch', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-nightly-running-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final r = runGate(
      runs: ['9718|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|running'],
      runningBecomesSuccess: true,
      trace: trace,
    );
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, 0, reason: output);
    expect(output, contains('DOOR'));
    expect(trace.readAsStringSync(), isNot(contains('POST ')));
  });

  test('een nieuw gedispatchte rode run blijft fail-closed', () {
    final r = runGate(runs: [], dispatchedStatus: 'failure');
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('https://forge.invalid/r/9800'));
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
