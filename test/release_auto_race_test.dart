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
WEBSITE_URL=https://website.invalid/nl/ocideck/
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
  if [ "\$1 \$2 \$3" = 'remote get-url mirror' ]; then return 0; fi
  case "\${*: -1}" in
    refs/heads/*) return 2 ;;
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
    https://forge.invalid/api/v1/repos/LibreKAT/Ocideck/releases/tags/v9.9.9)
      printf '%s\\n' '{"id":41,"assets":[{"name":"SHA256SUMS"},{"name":"SHA256SUMS.minisig"}]}' >"\$out"
      printf '200'
      ;;
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

    // Elke functiebody uit dit script — cmd_status roept zijn sondes op in
    // subshells (#2305), en die zoeken hún callees ook pas bij aanroepen. De
    // regel "gedefinieerd vóór de aanroep" geldt dus transitief: niet alleen
    // wat cmd_status letterlijk noemt, maar ook wat de sondes noemen.
    final bodies = <String, String>{};
    for (final name in defined.keys) {
      final start = defined[name]!;
      final end = lines.indexWhere(
        (l) => RegExp(r'^\}\s*$').hasMatch(l),
        start,
      );
      bodies[name] = lines.sublist(start + 1, end).join('\n');
    }
    final used = <String>{};
    final queue = <String>['cmd_status'];
    while (queue.isNotEmpty) {
      final body = bodies[queue.removeLast()];
      if (body == null) continue;
      for (final f in defined.keys) {
        if (used.contains(f)) continue;
        if (RegExp('(^|[^a-zA-Z0-9_])$f([^a-zA-Z0-9_]|\$)').hasMatch(body)) {
          used.add(f);
          queue.add(f);
        }
      }
    }
    used.remove('cmd_status');
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
  ProcessResult runStatus({
    required String liveVersion,
    String websiteVersion = '9.9.9',
    String pullsJson = '[]',
    bool releaseMissing = false,
  }) {
    final state = Directory.systemTemp.createTempSync('ocideck-status-');
    final live = File('${state.path}/live.txt')..writeAsStringSync(liveVersion);
    final website = File('${state.path}/website.html')
      ..writeAsStringSync(
        '<a href="https://forge.invalid/releases/download/v$websiteVersion/'
        'ocideck-linux-amd64-$websiteVersion.deb">deb</a>\n'
        '<a href="https://forge.invalid/releases/download/v$websiteVersion/'
        'ocideck-linux-x86_64-$websiteVersion.AppImage">appimage</a>\n'
        '<a href="https://forge.invalid/releases/download/v$websiteVersion/'
        'ocideck-macos-$websiteVersion.zip">mac</a>\n'
        '<a href="https://forge.invalid/releases/download/v$websiteVersion/'
        'ocideck-windows-x64-setup-$websiteVersion.exe">windows</a>\n',
      );
    addTearDown(() => state.deleteSync(recursive: true));
    return runReleaseHarness('''
LIVE=${live.path}
WEBSITE=${website.path}
BRANCH=release/v9.9.9
read_token() { :; }
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
mark() { printf 'mark %s %s\\n' "\$1" "\$2"; }
git() {
  if [ "\$1 \$2 \$3" = 'remote get-url mirror' ]; then return 0; fi
  case "\${*: -1}" in
    refs/heads/*) return 2 ;;
    refs/tags/*) return 0 ;;
  esac
  return 1
}
api() {
  case "\$2" in
    '/actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"success"}]}'
      ;;
    '/actions/runs/900/jobs')
      printf '%s\\n' '[{"name":"Release publiceren","status":"success","id":1,"attempt":1}]'
      ;;
    '/pulls?state=all&limit=50') printf '%s\\n' '$pullsJson' ;;
    '/releases/tags/v9.9.9')
      ${releaseMissing ? 'return 22' : '''printf '%s\\n' '{"id":41,"assets":[{"name":"SHA256SUMS"},{"name":"SHA256SUMS.minisig"}]}' '''}
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
curl() {
  local out='' url='' previous='' arg write_code=0
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ] || [[ "\$previous" == *o ]]; then out="\$arg"; fi
    [ "\$previous" = '-w' ] && write_code=1
    previous="\$arg"; url="\$arg"
  done
  case "\$url" in
    https://forge.invalid/api/v1/repos/LibreKAT/Ocideck/releases/tags/v9.9.9)
      ${releaseMissing ? "printf '404'" : '''printf '%s\\n' '{"id":41,"assets":[{"name":"SHA256SUMS"},{"name":"SHA256SUMS.minisig"}]}' >"\$out"; printf '200' '''}
      ;;
    https://website.invalid/nl/ocideck/)
      command cat "\$WEBSITE"
      ;;
    */version.json)
      v="\$(cat "\$LIVE")"
      [ -n "\$v" ] || return 22
      printf '{"version":"%s"}\\n' "\$v"
      ;;
    */SHA256SUMS.minisig) printf 'signature:manifest-A\\n' >"\$out" ;;
    */SHA256SUMS)
      for asset in \$(expected_release_assets); do
        printf '%064d  ./%s\\n' 0 "\$asset"
      done >"\$out"
      ;;
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
      expect(output, contains('--resume v9.9.9'));
      expect(
        output,
        isNot(contains('git checkout')),
        reason:
            'het advies mag geen losse checkout+deploy meer tonen: die omzeilt '
            'de schone-werkboom- en tag-tegen-origin-controles (#2295).',
      );
    },
    skip: skipOnWindows,
  );

  test(
    '--status noemt een release met een live demo en downloadpagina compleet',
    () {
      final r = runStatus(liveVersion: '9.9.9');
      final output = '${r.stdout}\n${r.stderr}';
      expect(output, contains('mark 1 webdemo'), reason: output);
      expect(output, contains('mark 1 downloadpagina'), reason: output);
      expect(output, contains('De release is publiek compleet'));
    },
    skip: skipOnWindows,
  );

  test('--status noemt een achtergebleven downloadpagina niet compleet', () {
    final r = runStatus(liveVersion: '9.9.9', websiteVersion: '9.9.8');
    final output = '${r.stdout}\n${r.stderr}';
    expect(output, contains('mark 0 downloadpagina'), reason: output);
    expect(output, contains('(nu: v9.9.8'));
    expect(
      output,
      isNot(contains('v9.9.89.9.8')),
      reason:
          'de huidige websiteversie hoort maar één keer in de status.\n$output',
    );
    expect(output, isNot(contains('De release is publiek compleet')));
    expect(output, contains('--resume controleert daarna de publieke pagina'));
  }, skip: skipOnWindows);

  test(
    '--status noemt een ontbrekende release afwezig, niet API-onleesbaar',
    () {
      final r = runStatus(liveVersion: '9.9.9', releaseMissing: true);
      final output = '${r.stdout}\n${r.stderr}';
      expect(output, contains('mark 0 release aangemaakt'), reason: output);
      expect(
        output,
        isNot(contains('[?] release aangemaakt')),
        reason:
            'HTTP 404 is bewezen afwezigheid, geen onleesbare API.\n$output',
      );
    },
    skip: skipOnWindows,
  );

  // De merge verwijdert de release-branch. Eén vast vakje "branch op origin"
  // bleef daardoor op élke afgeronde release leeg staan en las als een open
  // punt in een lijst waarin alles afgevinkt hoort te zijn.
  test('--status ziet een opgeruimde release-branch als de goede afloop', () {
    final r = runStatus(
      liveVersion: '9.9.9',
      pullsJson:
          '[{"title":"chore(release): versie 9.9.9","number":7,'
          '"state":"closed","merged":true}]',
    );
    final output = '${r.stdout}\n${r.stderr}';
    expect(output, contains('mark 1 release-branch'), reason: output);
    expect(output, contains('opgeruimd bij de merge'));
    expect(output, isNot(contains('mark 0 release-branch')));
  }, skip: skipOnWindows);

  test('--status meldt een nog openstaande release-branch als voortgang', () {
    final r = runStatus(liveVersion: '9.9.9');
    final output = '${r.stdout}\n${r.stderr}';
    expect(
      output,
      contains('mark 0 release-branch release/v9.9.9 op origin'),
      reason:
          'zonder gemergede PR is de branch juist het teken van voortgang'
          '\n$output',
    );
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
  if [ "\$1" = GET ] && [ "\$2" = '/actions/runs?limit=50&workflow_id=release.yml' ]; then
    printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"running"}]}'
    return 0
  fi
  if [ "\$1" = GET ] && [ "\$2" = '/actions/runs/900/jobs' ]; then
    printf '%s\\n' '[{"name":"Publiceren","status":"running","id":1,"attempt":1}]'
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

  test('follow_ci houdt een wall-clockdeadline aan bij een trage poll', () {
    final polls = File(
      '${Directory.systemTemp.path}/ocideck-ci-deadline-$pid.log',
    );
    addTearDown(() {
      if (polls.existsSync()) polls.deleteSync();
    });
    final stopwatch = Stopwatch()..start();
    final result = runReleaseHarness('''
POLLS=${polls.path}
RELEASE_CI_TIMEOUT_MIN=0
RELEASE_CI_TIMEOUT_SECONDS=2
section() { :; }
log() { :; }
sleep() { :; }
release_ci_snapshot() {
  printf 'poll\\n' >>"\$POLLS"
  command sleep 3
  printf '%s\n' 'running|Linux bouwen'
}
release_ci_completion_seen() { return 1; }
die() { printf 'DIE: %s\n' "\$1" >&2; exit 99; }
follow_ci
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
          'terugkeer betekent dat RELEASE_CI_TIMEOUT_SECONDS is genegeerd.',
    );
    expect(polls.readAsLinesSync(), ['poll']);
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
  case "\$1 \$2" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      # De losse ci.yml-run op dezelfde tag mag de release-snapshot niet raken.
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"running"},{"id":901,"prettyref":"v9.9.9","workflow_id":"ci.yml","status":"failure"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      n=\$(( \$(cat "\$COUNTER" 2>/dev/null || echo 0) + 1 )); printf '%s' "\$n" >"\$COUNTER"
      if [ "\$n" -lt 150 ]; then
        printf '%s\\n' '[{"name":"Linux bouwen","status":"running","id":1,"attempt":1},{"name":"macOS bouwen","status":"success","id":2,"attempt":1}]'
      else
        printf '%s\\n' '[{"name":"Linux bouwen","status":"success","id":1,"attempt":1},{"name":"macOS bouwen","status":"success","id":2,"attempt":1},{"name":"Release publiceren","status":"success","id":3,"attempt":1}]'
      fi
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
follow_ci
echo "KLAAR"
''');
    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(result.stdout, endsWith('KLAAR\n'));
    expect(int.parse(counter.readAsStringSync()), greaterThanOrEqualTo(150));
    // Een hartslag om de tien minuten laat zien dat er gewacht wordt, niet gehangen.
    expect(result.stdout, contains('nog bezig na'));
    // De losse ci.yml-poort hoort niet eens in de release.yml-snapshot.
    expect(result.stdout, isNot(contains('losse ci.yml-poort (gate)')));
    expect(result.stdout, isNot(contains('minstens één release-job faalde')));
  }, skip: skipOnWindows);

  test('een gefaalde releasejob wordt wél als zodanig gemeld', () {
    final result = runReleaseHarness('''
section() { :; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() {
  case "\$1 \$2" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"failure"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      printf '%s\\n' '[{"name":"Linux bouwen","status":"failure","id":1,"attempt":1},{"name":"Release publiceren","status":"failure","id":2,"attempt":1}]'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
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
    ls-remote) printf '%s refs/tags/v9.9.9^{}\\n' '$tagSha' ;;
    *) return 1 ;;
  esac
}
api() {
  case "\$1 \$2" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"success"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      printf '%s\\n' "[$snapshotJobs]"
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
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
          '{"name":"Webversie live zetten","status":"success","id":1,"attempt":1}',
    );
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, contains('draait nog 0.6.4'));
    expect(r.stderr, contains('make deploy-web'));
    expect(r.stdout, contains('draait 9.9.9'));
  }, skip: skipOnWindows);

  // Sinds fase 3 de werkboom zélf op de tag zet (de release-PR landt met een
  // merge-commit, dus HEAD kán de tag niet zijn) is "HEAD is niet de tag" geen
  // reden meer om te stoppen — mislukken van die verhuizing wél. Deze stub-git
  // weigert `diff` en `checkout`, precies het geval waarin niets gepubliceerd mag
  // worden. De geslaagde route staat in release_auto_deploy_tag_test.dart, op een
  // echte repo met een echte merge-commit.
  test(
    'fase 3 publiceert niets als de werkboom niet op de tag te krijgen is',
    () {
      final r = runDeployWeb(liveVersion: '0.6.4', headSha: 'ergens-op-main');
      expect(r.exitCode, 1);
      expect(r.stderr, contains('DIE:'));
      expect(r.stderr, contains('--resume v9.9.9'));
      expect(r.stderr, isNot(contains('make deploy-web')));
    },
    skip: skipOnWindows,
  );

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
  if [ "\$1" = GET ] && [ "\$2" = '/actions/runs?limit=50&workflow_id=release.yml' ]; then
    printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"running"}]}'
    return 0
  fi
  if [ "\$1" = GET ] && [ "\$2" = '/actions/runs/900/jobs' ]; then
    printf '%s\\n' '[{"name":"Publiceren","status":"running","id":1,"attempt":1}]'
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

  test('terminale releasefout wordt niet blind opnieuw gedispatcht', () {
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
  case "\$url" in
    https://website.invalid/nl/ocideck/)
      printf '<a href="https://forge.invalid/releases/download/v9.9.9/ocideck.zip">download</a>\\n'
      return 0
      ;;
  esac
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
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"failure"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      printf '%s\\n' '[{"name":"Release publiceren","status":"failure","id":101,"attempt":1}]'
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
    expect(events.where((event) => event == 'dispatch'), isEmpty);
    final signEvents = events
        .where((event) => event.startsWith('sign-after-'))
        .toList();
    expect(signEvents, isEmpty);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('failure/cancelled/skipped/error'));
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
      for asset in \$(expected_release_assets); do
        if [ "\$SUM_DOWNLOADS" -eq 1 ]; then hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; else hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; fi
        printf '%s  ./%s\\n' "\$hash" "\$asset"
      done >"\$out"
      ;;
    *) return 22 ;;
  esac
}
minisign() { printf 'verify\\n' >>"\$TRACE"; return 0; }
api() {
  case "\$1 \$2" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"success"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      printf '%s\\n' '[{"name":"Release publiceren","status":"success","id":1,"attempt":1},{"name":"Website-downloads bijwerken","status":"success","id":2,"attempt":1}]'
      ;;
    'GET /releases/tags/v9.9.9') printf '%s\\n' '{"id":41}' ;;
    'GET /releases/41/assets')
      printf '%s\\n' '[{"name":"ocideck-web-9.9.9.tar.gz"},{"name":"ocideck-linux-x64-9.9.9.tar.gz"},{"name":"ocideck-linux-amd64-9.9.9.deb"},{"name":"ocideck-linux-x86_64-9.9.9.rpm"},{"name":"ocideck-linux-x86_64-9.9.9.AppImage"},{"name":"ocideck-macos-9.9.9.zip"},{"name":"ocideck-windows-x64-9.9.9.zip"},{"name":"ocideck-windows-x64-setup-9.9.9.exe"},{"name":"ocideck-9.9.9.cdx.json"},{"name":"ocideck-9.9.9.spdx.json"},{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"},{"name":"SHA256SUMS.minisig","browser_download_url":"https://dl.invalid/x/SHA256SUMS.minisig"}]'
      ;;
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
