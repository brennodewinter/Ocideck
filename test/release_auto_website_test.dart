import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressies voor de publieke website-naconditie van fase 3.
///
/// Alle functies uit `release_auto.sh` draaien echt. Alleen de grenzen naar de
/// forge, downloads, webdemo, downloadpagina, ondertekenaar en wachttijd zijn
/// vervangen. Daardoor kan een groene website-job nooit als vervanging dienen
/// voor wat een bezoeker op librekat.nl daadwerkelijk krijgt.
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

  ProcessResult runPhase3({
    required String websiteVersion,
    String websiteRun = '',
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-release-website-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final page = File('${dir.path}/website.html')
      ..writeAsStringSync('''
<!doctype html>
<a href="https://forge.invalid/releases/download/v$websiteVersion/ocideck-linux-amd64-$websiteVersion.deb">
  OciDeck $websiteVersion downloaden
</a>
<a href="https://forge.invalid/releases/download/v$websiteVersion/ocideck-linux-x86_64-$websiteVersion.AppImage">AppImage</a>
<a href="https://forge.invalid/releases/download/v$websiteVersion/ocideck-macos-$websiteVersion.zip">macOS</a>
<a href="https://forge.invalid/releases/download/v$websiteVersion/ocideck-windows-x64-setup-$websiteVersion.exe">Windows</a>
''');
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
WEBSITE_RUN=$websiteRun
TMP=
STEP=test
snap=
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
sleep() { :; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
make() {
  if [ "\$1" = sign-release ]; then
    local arg sums=''
    for arg in "\$@"; do
      case "\$arg" in SHA256SUMS=*) sums="\${arg#SHA256SUMS=}" ;; esac
    done
    printf 'signature\\n' >"\$sums.minisig"
  fi
}
minisign() { return 0; }
api() {
  local method="\$1" path="\$2"
  case "\$method \$path" in
    'GET /actions/runs?limit=50&workflow_id=release.yml')
      printf '%s\\n' '{"workflow_runs":[{"id":900,"prettyref":"v9.9.9","workflow_id":"release.yml","status":"success"}]}'
      ;;
    'GET /actions/runs/900/jobs')
      printf '%s\\n' '[{"name":"Release publiceren","status":"success","id":1,"attempt":1}]'
      ;;
    'GET /actions/runs?limit=50&workflow_id=website-downloads.yml')
      if [ -n "\$WEBSITE_RUN" ]; then
        printf '{"workflow_runs":[{"id":901,"prettyref":"v9.9.9","workflow_id":"website-downloads.yml","status":"%s"}]}\\n' "\$WEBSITE_RUN"
      else
        printf '%s\\n' '{"workflow_runs":[]}'
      fi
      ;;
    'GET /releases/41/assets')
      printf '%s\\n' '[{"name":"ocideck-web-9.9.9.tar.gz"},{"name":"ocideck-linux-x64-9.9.9.tar.gz"},{"name":"ocideck-linux-amd64-9.9.9.deb"},{"name":"ocideck-linux-x86_64-9.9.9.rpm"},{"name":"ocideck-linux-x86_64-9.9.9.AppImage"},{"name":"ocideck-macos-9.9.9.zip"},{"name":"ocideck-windows-x64-9.9.9.zip"},{"name":"ocideck-windows-x64-setup-9.9.9.exe"},{"name":"ocideck-9.9.9.cdx.json"},{"name":"ocideck-9.9.9.spdx.json"},{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"},{"name":"SHA256SUMS.minisig","browser_download_url":"https://dl.invalid/x/SHA256SUMS.minisig"}]'
      ;;
    'GET /releases/tags/v9.9.9') printf '%s\\n' '{"id":41}' ;;
    POST\\ /releases/41/assets?name=SHA256SUMS.minisig.new.*)
      printf '%s\\n' '{"id":77}'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ]; then out="\$arg"; fi
    previous="\$arg"
    url="\$arg"
  done
  case "\$url" in
    https://demo.invalid/version.json)
      printf '%s\\n' '{"version":"9.9.9"}'
      ;;
    https://website.invalid/nl/ocideck/)
      command cat '${page.path}'
      ;;
    */SHA256SUMS.minisig)
      printf 'signature\\n' >"\$out"
      ;;
    */SHA256SUMS)
      for asset in \$(expected_release_assets); do
        printf '%064d  ./%s\\n' 0 "\$asset"
      done >"\$out"
      ;;
    *) return 22 ;;
  esac
}
phase3
printf 'DOOR\\n'
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  test(
    'groene website-job is onvoldoende als de publieke pagina achterloopt',
    () {
      // De website-run zelf is groen — toch mag een achterlopende publieke
      // pagina nooit als "klaar" gelden (#2302: pas díe combinatie mag als
      // host/DNS-verwijzing verschijnen).
      final result = runPhase3(websiteVersion: '9.9.8', websiteRun: 'success');
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, isNot(0), reason: output);
      expect(output, contains('v9.9.8'));
      expect(output, contains('in plaats van v9.9.9'));
      expect(output, contains('--resume v9.9.9'));
      expect(output, isNot(contains('DOOR')));
    },
    skip: skipOnWindows,
  );

  test('fase 3 rondt af als de publieke pagina naar de release verwijst', () {
    final result = runPhase3(websiteVersion: '9.9.9');
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(
      output,
      contains(
        'Publieke downloadpagina gecontroleerd: '
        'https://website.invalid/nl/ocideck/ verwijst naar v9.9.9.',
      ),
    );
    expect(output, contains('DOOR'));
  }, skip: skipOnWindows);
}
