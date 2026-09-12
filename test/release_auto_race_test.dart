import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressies voor de v0.6.2-race in `scripts/release_auto.sh`.
///
/// De echte bashfuncties draaien in een hermetisch harnas. Alleen hun externe
/// grenzen (Forgejo, downloads, make, sleep en minisign) zijn gemockt. Zo bewijzen
/// deze tests de release-toestandsovergangen zonder netwerk, sleutel of wachttijd.
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

  ProcessResult runReleaseHarness(String mocksAndCall) {
    final dir = Directory.systemTemp.createTempSync('ocideck-release-race-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
ROOT_DIR=${Directory.current.path}
RELEASE_BASE_URL=https://releases.invalid/download
FORGE_API=https://forge.invalid/api/v1
REPO_SLUG=LibreKAT/Ocideck
TOKEN=test-token
MINISIGN_PW=test-password
TMP=
STEP=test
snap=
${allFunctionDefinitions()}
$mocksAndCall
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  test(
    '--status noemt een aanwezige maar ongeldige handtekening niet compleet',
    () {
      final trace = File(
        '${Directory.systemTemp.path}/ocideck-status-verify-$pid.log',
      );
      addTearDown(() {
        if (trace.existsSync()) trace.deleteSync();
      });
      final result = runReleaseHarness('''
TRACE=${trace.path}
BRANCH=release/v9.9.9
read_token() { :; }
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
git() {
  if [ "\$1 \$2" = 'remote get-url' ]; then return 1; fi
  case "\${*: -1}" in
    refs/heads/*) return 1 ;;
    refs/tags/*) return 0 ;;
  esac
  return 1
}
api() {
  case "\$2" in
    '/pulls?state=all&limit=50') printf '%s\\n' '[]' ;;
    '/releases/tags/v9.9.9')
      printf '%s\\n' '{"id":41,"assets":[{"name":"SHA256SUMS"},{"name":"SHA256SUMS.minisig"}]}'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ] || [[ "\$previous" == *o ]]; then out="\$arg"; fi
    previous="\$arg"; url="\$arg"
  done
  case "\$url" in
    */SHA256SUMS.minisig) printf 'signature:manifest-A\\n' >"\$out" ;;
    */SHA256SUMS) printf 'manifest-B\\n' >"\$out" ;;
    *) return 22 ;;
  esac
}
minisign() { printf 'verify\\n' >>"\$TRACE"; return 1; }
cmd_status
''');

      final output = '${result.stdout}\n${result.stderr}';
      expect(
        trace.existsSync() ? trace.readAsLinesSync() : <String>[],
        contains('verify'),
        reason: '--status moet de publieke bestanden met minisign toetsen.',
      );
      expect(
        output,
        isNot(contains('De release lijkt compleet')),
        reason:
            'een ongeldige publieke handtekening is niet compleet.\n$output',
      );
    },
    skip: skipOnWindows,
  );

  test('een actieve release-CI mag na de wachttijd niet stil doorlopen', () {
    final mutations = File(
      '${Directory.systemTemp.path}/ocideck-release-mutations-$pid.log',
    );
    addTearDown(() {
      if (mutations.existsSync()) mutations.deleteSync();
    });
    final result = runReleaseHarness('''
MUTATIONS=${mutations.path}
section() { :; }
log() { :; }
sleep() { :; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
api() {
  if [ "\$1" = GET ] && [ "\$2" = '/actions/tasks?limit=25' ]; then
    printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"running","name":"Publiceren"}]}'
    return 0
  fi
  printf '%s %s\\n' "\$1" "\$2" >>"\$MUTATIONS"
}
follow_ci
''');

    expect(
      result.exitCode,
      isNot(0),
      reason:
          'follow_ci moet bij een blijvend actieve job fail-closed stoppen.',
    );
    expect(
      mutations.existsSync() ? mutations.readAsStringSync() : '',
      isEmpty,
      reason: 'de timeout-controle mag niets muteren.',
    );
  }, skip: skipOnWindows);

  test('fase 3 herdispatcht niet zolang dezelfde release-CI nog actief is', () {
    final mutations = File(
      '${Directory.systemTemp.path}/ocideck-release-dispatch-$pid.log',
    );
    addTearDown(() {
      if (mutations.existsSync()) mutations.deleteSync();
    });
    final result = runReleaseHarness('''
MUTATIONS=${mutations.path}
section() { :; }
log() { :; }
sleep() { :; }
make() { return 0; }
curl() { return 22; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
api() {
  if [ "\$1" = GET ] && [ "\$2" = '/actions/tasks?limit=25' ]; then
    printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"running","name":"Publiceren"}]}'
    return 0
  fi
  if [ "\$1" != GET ]; then printf '%s %s\\n' "\$1" "\$2" >>"\$MUTATIONS"; fi
  printf '%s\\n' '{}'
}
phase3
''');

    final mutationLog = mutations.existsSync()
        ? mutations.readAsStringSync()
        : '';
    expect(
      mutationLog,
      isNot(contains('workflows/release.yml/dispatches')),
      reason: 'een actieve publiceren-job mag geen tweede schrijver krijgen.',
    );
    expect(result.exitCode, isNot(0));
  }, skip: skipOnWindows);

  test('herstel wacht op een nieuwe terminale CI-run vóór het tekenen', () {
    final state = Directory.systemTemp.createTempSync(
      'ocideck-release-redispatch-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final calls = File('${state.path}/calls')..writeAsStringSync('0');
    final trace = File('${state.path}/trace');
    final dispatched = File('${state.path}/dispatched');

    final result = runReleaseHarness('''
CALLS=${calls.path}
TRACE=${trace.path}
DISPATCHED=${dispatched.path}
section() { :; }
log() { :; }
sleep() { :; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
make() {
  [ "\${1:-}" = deploy-web ] && return 0
  local arg sums=''
  for arg in "\$@"; do
    case "\$arg" in SHA256SUMS=*) sums="\${arg#SHA256SUMS=}" ;; esac
  done
  [ -n "\$sums" ] || return 1
  printf 'sign-after-%s\\n' "\$(cat "\$CALLS")" >>"\$TRACE"
  printf 'signature:manifest-A\\n' >"\$sums.minisig"
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ] || [[ "\$previous" == *o ]]; then out="\$arg"; fi
    previous="\$arg"; url="\$arg"
  done
  [ -f "\$DISPATCHED" ] || return 22
  case "\$url" in
    */SHA256SUMS.minisig) printf 'signature:manifest-A\\n' >"\$out" ;;
    */SHA256SUMS) printf 'manifest-A\\n' >"\$out" ;;
    *) return 22 ;;
  esac
}
minisign() { return 0; }
api() {
  local method="\$1" path="\$2" count
  case "\$method \$path" in
    'GET /actions/tasks?limit=25')
      count=\$(( \$(cat "\$CALLS") + 1 ))
      printf '%s' "\$count" >"\$CALLS"
      if [ "\$count" -le 3 ]; then
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Publiceren"}]}'
      elif [ "\$count" -eq 4 ]; then
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Publiceren"},{"id":202,"head_branch":"v9.9.9","status":"running","name":"Publiceren"}]}'
      else
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Publiceren"},{"id":202,"head_branch":"v9.9.9","status":"success","name":"Publiceren"}]}'
      fi
      ;;
    'POST /actions/workflows/release.yml/dispatches')
      printf 'dispatch\\n' >>"\$TRACE"
      : >"\$DISPATCHED"
      printf '%s\\n' '{}'
      ;;
    'GET /releases/tags/v9.9.9') printf '%s\\n' '{"id":41}' ;;
    'GET /releases/41/assets') printf '%s\\n' '[]' ;;
    POST*) printf '%s\\n' '{"id":42}' ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
phase3
''');

    final events = trace.existsSync() ? trace.readAsLinesSync() : <String>[];
    expect(
      events.where((event) => event == 'dispatch').length,
      1,
      reason: 'een terminale mislukking krijgt exact één herstel-dispatch.',
    );
    final signEvents = events
        .where((event) => event.startsWith('sign-after-'))
        .toList();
    expect(signEvents, hasLength(1));
    final pollsAtSigning = int.parse(signEvents.single.split('-').last);
    expect(
      pollsAtSigning,
      greaterThanOrEqualTo(5),
      reason:
          'de oude terminale task 101 bewijst niet dat de herdispatch klaar '
          'is. Fase 3 moet eerst task 202 zien en terminaal afwachten.\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(result.exitCode, 0);
  }, skip: skipOnWindows);

  test('fase 3 wijst een na tekenen vervangen publiek manifest af', () {
    final trace = File(
      '${Directory.systemTemp.path}/ocideck-release-verify-$pid.log',
    );
    addTearDown(() {
      if (trace.existsSync()) trace.deleteSync();
    });
    final result = runReleaseHarness('''
TRACE=${trace.path}
SUM_DOWNLOADS=0
section() { :; }
log() { :; }
sleep() { :; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
make() {
  [ "\${1:-}" = deploy-web ] && return 0
  local arg sums=''
  for arg in "\$@"; do
    case "\$arg" in SHA256SUMS=*) sums="\${arg#SHA256SUMS=}" ;; esac
  done
  [ -n "\$sums" ] || return 1
  printf 'signature:manifest-A\\n' >"\$sums.minisig"
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ] || [[ "\$previous" == *o ]]; then out="\$arg"; fi
    previous="\$arg"; url="\$arg"
  done
  case "\$url" in
    */SHA256SUMS.minisig) printf 'signature:manifest-A\\n' >"\$out" ;;
    */SHA256SUMS)
      SUM_DOWNLOADS=\$((SUM_DOWNLOADS + 1))
      printf 'sums-download-%s\\n' "\$SUM_DOWNLOADS" >>"\$TRACE"
      if [ "\$SUM_DOWNLOADS" -eq 1 ]; then
        printf 'manifest-A\\n' >"\$out"
      else
        printf 'manifest-B\\n' >"\$out"
      fi
      ;;
    *) return 22 ;;
  esac
}
minisign() { printf 'verify\\n' >>"\$TRACE"; return 0; }
api() {
  case "\$1 \$2" in
    'GET /actions/tasks?limit=25')
      printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"success","name":"Publiceren"}]}'
      ;;
    'GET /releases/tags/v9.9.9') printf '%s\\n' '{"id":41}' ;;
    'GET /releases/41/assets') printf '%s\\n' '[]' ;;
    POST*) printf '%s\\n' '{"id":42}' ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
phase3
''');

    final calls = trace.existsSync() ? trace.readAsLinesSync() : <String>[];
    expect(
      calls.where((line) => line.startsWith('sums-download-')).length,
      greaterThanOrEqualTo(2),
      reason: 'fase 3 moet het publieke manifest na upload teruglezen.',
    );
    expect(
      result.exitCode,
      isNot(0),
      reason: 'manifest-B hoort niet bij de getekende lokale manifest-A.',
    );
  }, skip: skipOnWindows);
}
