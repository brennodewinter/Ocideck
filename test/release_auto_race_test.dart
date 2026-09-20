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
DEPLOY_URL=https://demo.invalid
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

  // Bash zoekt een functie pas op het moment van aanroepen. `--status` roept
  // cmd_status aan op ongeveer regel 512, en alles wat die functie gebruikt
  // moet dáárvóór gedefinieerd zijn. Stond `live_web_version` bij fase 3, dan
  // zocht bash een programma met die naam; de MacPorts-bash van de bouw-Mac
  // eindigt dat niet met "command not found" maar met een segfault in
  // CoreFoundation — drie keer achtereen gereproduceerd op 20-09-2026.
  // De harnas-toetsen hierboven zien dit niet: die plakken álle functies vóór
  // de aanroep en maken de volgorde in het bestand juist onzichtbaar.
  test('elke functie die cmd_status gebruikt, staat vóór de aanroep', () {
    final lines = File(script).readAsLinesSync();
    final defined = <String, int>{};
    final open = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(\)\s*\{');
    for (var i = 0; i < lines.length; i++) {
      final m = open.firstMatch(lines[i]);
      if (m != null) defined.putIfAbsent(m.group(1)!, () => i);
    }
    final callSite = lines.indexWhere((l) => l.trim() == 'cmd_status');
    expect(
      callSite,
      greaterThan(0),
      reason: 'aanroep van cmd_status niet gevonden',
    );

    // De body van cmd_status, en daarin elk woord dat een functie uit dit
    // script is.
    final start = defined['cmd_status']!;
    final end = lines.indexWhere((l) => RegExp(r'^\}\s*$').hasMatch(l), start);
    final body = lines.sublist(start + 1, end).join('\n');
    final used = defined.keys
        .where((f) => f != 'cmd_status')
        .where(
          (f) => RegExp('(^|[^a-zA-Z0-9_])$f([^a-zA-Z0-9_]|\$)').hasMatch(body),
        )
        .toList();
    expect(
      used,
      contains('live_web_version'),
      reason: 'de webdemo hoort in het statusrapport',
    );
    for (final f in used) {
      expect(
        defined[f]!,
        lessThan(callSite),
        reason:
            'cmd_status gebruikt $f (regel ${defined[f]! + 1}), maar de aanroep '
            'staat op regel ${callSite + 1}; bash kent de functie dan nog niet.',
      );
    }
  }, skip: skipOnWindows);

  // --status rapporteerde de webdemo niet; het advies zei "controleer nog de
  // live web-versie", en dat deed niemand. v0.6.5 en v0.6.6 stonden compleet in
  // het rapport terwijl de demo op 0.6.4 bleef staan.
  ProcessResult runStatus({required String liveVersion}) {
    final live = File(
      '${Directory.systemTemp.path}/ocideck-status-live-$pid.txt',
    )..writeAsStringSync(liveVersion);
    addTearDown(() {
      if (live.existsSync()) live.deleteSync();
    });
    return runReleaseHarness('''
LIVE=${live.path}
BRANCH=release/v9.9.9
read_token() { :; }
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
mark() { printf 'mark %s %s\\n' "\$1" "\$2"; }
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
    */version.json)
      v="\$(cat "\$LIVE")"
      [ -n "\$v" ] || return 22
      printf '{"version":"%s"}\\n' "\$v"
      ;;
    */SHA256SUMS.minisig) printf 'signature:manifest-A\\n' >"\$out" ;;
    */SHA256SUMS) printf 'manifest-A\\n' >"\$out" ;;
    *) return 22 ;;
  esac
}
minisign() { return 0; }
cmd_status
''');
  }

  test(
    '--status noemt een release met een achtergebleven webdemo niet compleet',
    () {
      final r = runStatus(liveVersion: '0.6.4');
      final output = '${r.stdout}\n${r.stderr}';
      expect(output, contains('mark 0 webdemo'), reason: output);
      expect(output, contains('(nu: 0.6.4)'));
      expect(output, isNot(contains('De release lijkt compleet')));
      expect(output, contains('make deploy-web'));
    },
    skip: skipOnWindows,
  );

  test('--status noemt een release met een live webdemo compleet', () {
    final r = runStatus(liveVersion: '9.9.9');
    final output = '${r.stdout}\n${r.stderr}';
    expect(output, contains('mark 1 webdemo'), reason: output);
    expect(output, contains('De release lijkt compleet'));
  }, skip: skipOnWindows);

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
  if [ "\$1" = GET ] && [ "\$2" = '/actions/tasks?limit=100' ]; then
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

  test('follow_ci wacht langer dan een uur zolang de keten zichtbaar draait', () {
    // v0.6.5: na 60 minuten (120 polls) brak de wacht af terwijl "Linux
    // bouwen" nog liep en elke andere job groen was; de keten werd 74 minuten
    // later netjes terminaal. Hier wordt de keten pas na 150 polls compleet.
    final counter = File(
      '${Directory.systemTemp.path}/ocideck-release-polls-$pid.log',
    );
    addTearDown(() {
      if (counter.existsSync()) counter.deleteSync();
    });
    final result = runReleaseHarness('''
COUNTER=${counter.path}
section() { :; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() {
  n=\$(( \$(cat "\$COUNTER" 2>/dev/null || echo 0) + 1 )); printf '%s' "\$n" >"\$COUNTER"
  if [ "\$n" -lt 150 ]; then
    printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"running","name":"Linux bouwen"},{"head_branch":"v9.9.9","status":"success","name":"macOS bouwen"},{"head_branch":"v9.9.9","status":"failure","name":"gate"}]}'
  else
    printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"success","name":"Linux bouwen"},{"head_branch":"v9.9.9","status":"success","name":"macOS bouwen"},{"head_branch":"v9.9.9","status":"failure","name":"gate"},{"head_branch":"v9.9.9","status":"success","name":"Website-downloads bijwerken"}]}'
  fi
}
follow_ci
echo "KLAAR"
''');
    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(result.stdout, endsWith('KLAAR\n'));
    expect(int.parse(counter.readAsStringSync()), greaterThanOrEqualTo(150));
    // Een hartslag om de tien minuten laat zien dat er gewacht wordt, niet gehangen.
    expect(result.stdout, contains('nog bezig na'));
    // De rode ci.yml-poort is een testuitslag naast de keten, geen releasejob.
    expect(result.stdout, contains('losse ci.yml-poort (gate)'));
    expect(result.stdout, isNot(contains('minstens één release-job faalde')));
  }, skip: skipOnWindows);

  test('een gefaalde releasejob wordt wél als zodanig gemeld', () {
    final result = runReleaseHarness('''
section() { :; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() {
  printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"failure","name":"Linux bouwen"},{"head_branch":"v9.9.9","status":"failure","name":"Release publiceren"}]}'
}
follow_ci
''');
    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(result.stdout, contains('minstens één release-job faalde'));
  }, skip: skipOnWindows);

  // Fase 3 bouwt de webdemo uit de wérkboom. Een --resume van v0.6.5 draaide
  // een dag later op main mét merges die niet in de tag zaten; alleen een
  // toevallig rode sbom-verify hield tegen dat die code als v0.6.5 live ging.
  // Of er gedeployd moet worden, beslist de live `version.json` — niet de
  // CI-job *Webversie live zetten*, die ook groen meldt als hij niets deed.
  //
  // [liveVersion] is wat de site vóór de deploy meldt (leeg = niet leesbaar),
  // [deployedVersion] wat hij erna meldt (standaard: de deploy werkt).
  ProcessResult runDeployWeb({
    required String liveVersion,
    required String headSha,
    String tagSha = 'tagsha000',
    String? deployedVersion,
    String snapshotJobs = '',
  }) {
    final calls = File(
      '${Directory.systemTemp.path}/ocideck-deploy-web-$pid.log',
    );
    final live = File(
      '${Directory.systemTemp.path}/ocideck-deploy-web-live-$pid.txt',
    )..writeAsStringSync(liveVersion);
    addTearDown(() {
      for (final f in [calls, live]) {
        if (f.existsSync()) f.deleteSync();
      }
    });
    final r = runReleaseHarness('''
CALLS=${calls.path}
LIVE=${live.path}
log() { printf '%s\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
# De site: leeg bestand = onbereikbaar (curl faalt), anders een version.json.
curl() {
  v="\$(cat "\$LIVE")"
  [ -n "\$v" ] || return 22
  printf '{"app_name":"ocideck","version":"%s","build_number":"1"}\\n' "\$v"
}
make() {
  printf 'make %s\\n' "\$*" >>"\$CALLS"
  [ "\$1" = deploy-web ] && printf '%s' '${deployedVersion ?? "9.9.9"}' >"\$LIVE"
  return 0
}
git() {
  case "\$1" in
    rev-list) printf '%s\\n' '$tagSha' ;;
    rev-parse) printf '%s\\n' '$headSha' ;;
    *) return 1 ;;
  esac
}
api() { printf '%s\\n' '{"workflow_runs":[$snapshotJobs]}'; }
deploy_web_if_needed
echo "DOOR"
''');
    // De make-aanroepen reizen mee in stderr van het resultaat, zodat één
    // ProcessResult volstaat.
    final made = calls.existsSync() ? calls.readAsStringSync() : '';
    return ProcessResult(r.pid, r.exitCode, r.stdout, '${r.stderr}$made');
  }

  test('fase 3 deployt niet als de demo de release al draait', () {
    final r = runDeployWeb(liveVersion: '9.9.9', headSha: 'ergens-op-main');
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, contains('draait al 9.9.9'));
    expect(r.stdout, endsWith('DOOR\n'));
    expect(r.stderr, isNot(contains('make deploy-web')));
  }, skip: skipOnWindows);

  test('een groene CI-job is geen bewijs: een oude demo wordt gedeployd', () {
    // v0.6.5 en v0.6.6 lieten de demo op 0.6.4 staan omdat de job *Webversie
    // live zetten* groen meldt terwijl hij overslaat (geen DEPLOY_SSH_KEY).
    final r = runDeployWeb(
      liveVersion: '0.6.4',
      headSha: 'tagsha000',
      snapshotJobs:
          '{"head_branch":"v9.9.9","status":"success","name":"Webversie live zetten"}',
    );
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, contains('draait nog 0.6.4'));
    expect(r.stderr, contains('make deploy-web'));
    expect(r.stdout, contains('draait 9.9.9'));
  }, skip: skipOnWindows);

  test('een oude demo naast de tag weigert fase 3 te deployen', () {
    final r = runDeployWeb(liveVersion: '0.6.4', headSha: 'ergens-op-main');
    expect(r.exitCode, 1);
    expect(r.stderr, contains('DIE:'));
    expect(r.stderr, contains('git checkout v9.9.9'));
    expect(r.stderr, isNot(contains('make deploy-web')));
  }, skip: skipOnWindows);

  test('een onleesbare site laat fase 3 vanaf de tag deployen', () {
    final r = runDeployWeb(liveVersion: '', headSha: 'tagsha000');
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, contains('niet lezen'));
    expect(r.stderr, contains('make deploy-web'));
  }, skip: skipOnWindows);

  test('een deploy die de demo niet verzet, laat fase 3 vallen', () {
    final r = runDeployWeb(
      liveVersion: '0.6.4',
      headSha: 'tagsha000',
      deployedVersion: '0.6.4',
    );
    expect(r.exitCode, 1);
    expect(r.stderr, contains('make deploy-web'));
    expect(r.stderr, contains('meldt 0.6.4 in plaats van 9.9.9'));
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
  if [ "\$1" = GET ] && [ "\$2" = '/actions/tasks?limit=100' ]; then
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

  test(
    'verdwenen baseline-task is geen bewijs van een nieuwe herdispatch-run',
    () {
      final result = runReleaseHarness('''
sleep() { :; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
release_ci_task_ids() { printf '%s\\n' 102; }
wait_for_redispatch_registration "\$(printf '101\\n102')"
''');

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'de overgang [101, 102] → [102] bevat geen nieuwe task-id. Een '
            'simpele ongelijkheidscontrole ziet het verdwijnen van 101 ten '
            'onrechte als registratie van de herstel-run.',
      );
    },
    skip: skipOnWindows,
  );

  test('een lege baseline-opvraag stopt vóór de herstel-dispatch', () {
    final state = Directory.systemTemp.createTempSync(
      'ocideck-release-empty-baseline-',
    );
    addTearDown(() => state.deleteSync(recursive: true));
    final calls = File('${state.path}/calls')..writeAsStringSync('0');
    final mutations = File('${state.path}/mutations');

    final result = runReleaseHarness('''
CALLS=${calls.path}
MUTATIONS=${mutations.path}
section() { :; }
log() { :; }
sleep() { :; }
make() { return 0; }
curl() { return 22; }
die() { printf '%s\\n' "\$1" >&2; exit 1; }
api() {
  local method="\$1" path="\$2" count
  if [ "\$method \$path" = 'GET /actions/tasks?limit=100' ]; then
    count=\$(( \$(cat "\$CALLS") + 1 ))
    printf '%s' "\$count" >"\$CALLS"
    if [ "\$count" -eq 1 ]; then
      printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Publiceren"}]}'
      return 0
    fi
    return 1
  fi
  if [ "\$method" != GET ]; then
    printf '%s %s\\n' "\$method" "\$path" >>"\$MUTATIONS"
  fi
  printf '%s\\n' '{}'
}
phase3
''');

    expect(result.exitCode, isNot(0));
    expect(
      mutations.existsSync() ? mutations.readAsStringSync() : '',
      isEmpty,
      reason:
          'zonder betrouwbare baseline kan de keten na POST niet bewijzen '
          'welke tasks nieuw zijn; zij moet daarom vóór POST stoppen.',
    );
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
git() { case "\$1" in rev-list|rev-parse) printf 'op-de-tag\\n' ;; *) return 1 ;; esac; }
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
  # De webdemo draait de release al; deze toets gaat over tekenen, niet over
  # deployen. Zonder dit antwoord valt fase 3 al bij deploy_web_if_needed.
  case "\$url" in */version.json) printf '{"version":"9.9.9"}\\n'; return 0 ;; esac
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
    'GET /actions/tasks?limit=100')
      count=\$(( \$(cat "\$CALLS") + 1 ))
      printf '%s' "\$count" >"\$CALLS"
      if [ "\$count" -le 3 ]; then
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Release publiceren"}]}'
      elif [ "\$count" -eq 4 ]; then
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Release publiceren"},{"id":202,"head_branch":"v9.9.9","status":"running","name":"Release publiceren"}]}'
      else
        printf '%s\\n' '{"workflow_runs":[{"id":101,"head_branch":"v9.9.9","status":"failure","name":"Release publiceren"},{"id":202,"head_branch":"v9.9.9","status":"success","name":"Release publiceren"},{"id":203,"head_branch":"v9.9.9","status":"success","name":"Website-downloads bijwerken"}]}'
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
git() { case "\$1" in rev-list|rev-parse) printf 'op-de-tag\\n' ;; *) return 1 ;; esac; }
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
    # De webdemo draait de release al; deze toets gaat over het manifest.
    */version.json) printf '{"version":"9.9.9"}\\n' ;;
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
    'GET /actions/tasks?limit=100')
      printf '%s\\n' '{"workflow_runs":[{"head_branch":"v9.9.9","status":"success","name":"Release publiceren"},{"head_branch":"v9.9.9","status":"success","name":"Website-downloads bijwerken"}]}'
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
