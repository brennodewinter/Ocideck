import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressie voor #2305: `--status` heeft een vaste totale deadline en meldt
/// elke sonde afzonderlijk als groen, afwezig of onbekend-met-reden.
///
/// Tijdens de v0.6.14-release bleef één Forgejo-endpoint muts terwijl andere
/// API-calls gewoon antwoordden. De oude --status deed elke probe sequentieel
/// met 4×90 s per GET — één hangende sonde blokkeerde alle uitvoer die erna
/// kwam, en een leesfout werd stil "afwezig". Nu draait elke sonde parallel
/// onder één deadline; wat de deadline niet haalt is expliciet onbekend.
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
    final dir = Directory.systemTemp.createTempSync('ocideck-status-deadline-');
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

  // Alles antwoordt, behalve de release-CI-sonde die muts blijft. Het commando
  // moet binnen de deadline eindigen, alle andere feiten tonen en alleen die
  // ene sonde als onbekend markeren.
  test(
    'een hangende API-sonde wordt alleen die sonde onbekend, binnen de deadline',
    () {
      final state = Directory.systemTemp.createTempSync('ocideck-status-');
      addTearDown(() => state.deleteSync(recursive: true));
      final website = File('${state.path}/website.html')
        ..writeAsStringSync(
          '<a href="https://forge.invalid/releases/download/v9.9.9/'
          'ocideck-linux-amd64-9.9.9.deb">deb</a>\n'
          '<a href="https://forge.invalid/releases/download/v9.9.9/'
          'ocideck-linux-x86_64-9.9.9.AppImage">appimage</a>\n'
          '<a href="https://forge.invalid/releases/download/v9.9.9/'
          'ocideck-macos-9.9.9.zip">mac</a>\n'
          '<a href="https://forge.invalid/releases/download/v9.9.9/'
          'ocideck-windows-x64-setup-9.9.9.exe">windows</a>\n',
        );
      final stopwatch = Stopwatch()..start();
      final result = runReleaseHarness('''
STATUS_TOTAL_SECONDS=4
BRANCH=release/v9.9.9
WEBSITE_HTML=${website.path}
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
    '/actions/runs?limit=50&workflow_id=release.yml') sleep 30 ;;
    '/actions/runs?limit=50&workflow_id=macos-gate.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":901,"prettyref":"v9.9.9","workflow_id":"macos-gate.yml","status":"success"}]}'
      ;;
    '/pulls?state=all&limit=50') printf '%s\\n' '[]' ;;
    '/releases/tags/v9.9.9') printf '%s\\n' '{"id":41,"assets":[]}' ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    [ "\$previous" = '-o' ] && out="\$arg"
    previous="\$arg"
    url="\$arg"
  done
  case "\$url" in
    https://forge.invalid/api/v1/repos/LibreKAT/Ocideck/releases/tags/v9.9.9)
      printf '%s\n' '{"id":41,"assets":[]}' >"\$out"
      printf '200'
      ;;
    https://website.invalid/nl/ocideck/) command cat "\$WEBSITE_HTML" ;;
    */version.json) printf '{"version":"9.9.9"}\\n' ;;
    *) return 22 ;;
  esac
}
minisign() { return 1; }
cmd_status
''');
      stopwatch.stop();
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason:
            '--status mag nooit langer duren dan de totale deadline '
            '(hier 4 s); dit duurde ${stopwatch.elapsed}.\n$output',
      );
      expect(
        output,
        contains('[?] release-CI terminaal groen'),
        reason: 'de hangende sonde hoort expliciet onbekend te zijn.\n$output',
      );
      expect(
        output,
        contains('tijdslimiet'),
        reason: 'de reden van de onbekende sonde hoort zichtbaar.\n$output',
      );
      // De overige feiten staan er gewoon: git, de release, de macos-gate en
      // de live webdemo waren allemaal bereikbaar.
      expect(output, contains('mark 1 tag v9.9.9 op origin'), reason: output);
      expect(output, contains('mark 0 release-PR aangemaakt'), reason: output);
      expect(output, contains('mark 1 release aangemaakt'), reason: output);
      expect(output, contains('macos-gate (goldens) op v9.9.9: success'));
      expect(output, contains('mark 1 webdemo'), reason: output);
      expect(
        RegExp(r'\[\?\]').allMatches(output).length,
        1,
        reason: 'alleen de getime-oute sonde is onbekend.\n$output',
      );
      expect(result.exitCode, 0, reason: output);
    },
    skip: skipOnWindows,
  );

  // De hele API muts: git- en web-feiten blijven zichtbaar, alle API-sondes
  // zijn onbekend en het advies noemt nooit een verse release voor een tag die
  // wél op origin staat.
  test('een helemaal onbereikbare API meldt alleen API-sondes onbekend', () {
    final stopwatch = Stopwatch()..start();
    final result = runReleaseHarness('''
STATUS_TOTAL_SECONDS=4
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
api() { sleep 30; }
curl() {
  local url='' arg
  for arg in "\$@"; do url="\$arg"; done
  case "\$url" in
    */version.json) printf '{"version":"9.9.9"}\\n' ;;
    *) return 22 ;;
  esac
}
minisign() { return 1; }
cmd_status
''');
    stopwatch.stop();
    final output = '${result.stdout}\n${result.stderr}';
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 20)),
      reason:
          'de deadline geldt ook als álles hangt; dit duurde '
          '${stopwatch.elapsed}.\n$output',
    );
    // Git-feiten zijn niet afhankelijk van de Forgejo-API.
    expect(output, contains('mark 1 tag v9.9.9 op origin'), reason: output);
    expect(
      output,
      contains('[?] release-PR'),
      reason: 'de PR-sonde was onbereikbaar, niet afwezig.\n$output',
    );
    expect(output, contains('[?] release aangemaakt'), reason: output);
    expect(
      output,
      contains('Maak DEZELFDE tag af'),
      reason:
          'met een tag op origin adviseert --status hervatten van dezelfde '
          'release, nooit een verse.\n$output',
    );
    expect(result.exitCode, 0, reason: output);
  }, skip: skipOnWindows);
}
