@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards #2303: `--resume` may only preflight the capabilities the still-open
/// steps need. A release whose signature is already valid and whose webdemo is
/// already live must reach the website-repair step without working deploy-SSH
/// or the minisign private key — earlier a full preflight blocked that resume
/// on capabilities it would never use. Unknown state stays fail-closed: if a
/// probe cannot be read, the capability is still demanded.
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

  /// Draait de echte `preflight` onder --resume met gemockte randvoorwaarden.
  /// [liveDemo]: de webdemo draait al de doelversie (deploy-SSH overbodig).
  /// [sigState]: 'valid' = manifest+minisig aanwezig én geldig; 'missing' =
  /// asset ontbreekt; 'absent' = de release bestaat nog niet.
  /// [mirrorTag]: de tag staat al op de mirror (of niet).
  /// De mock laat de ongebruikte capaciteiten expres falen: ssh sterft, make
  /// sign-release produceert niets, een loze mirror-ls-remote sterft — als de
  /// pre-flight ze tóch vraagt terwijl de stappen af zijn, valt de test.
  ProcessResult runPreflight({
    String resumeTag = 'v9.9.9',
    bool liveDemo = true,
    String sigState = 'valid',
    bool mirrorTag = true,
    bool mirrorReachable = true,
    bool deployReachable = false,
    bool keyWorks = false,
    bool presetPassword = true,
  }) {
    final dir = Directory.systemTemp.createTempSync(
      'ocideck-resume-preflight-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    // Een nagebouwde werkboom als ROOT_DIR (zoals de cache-preflight-test):
    // prune_stale_hook_cache.sh ziet hier geen bouwcaches en minisign.pub is
    // gekopieerd voor de geldig-heidsproef van de handtekening.
    final root = Directory('${dir.path}/tree')..createSync();
    Link(
      '${root.path}/scripts',
    ).createSync('${Directory.current.path}/scripts');
    Directory('${root.path}/.dart_tool').createSync();
    File(
      '${Directory.current.path}/minisign.pub',
    ).copySync('${root.path}/minisign.pub');
    final assetsJson = sigState == 'absent'
        ? '[]'
        : sigState == 'missing'
        ? '[{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"}]'
        : '[{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"},'
              '{"name":"SHA256SUMS.minisig","browser_download_url":"https://dl.invalid/x/SHA256SUMS.minisig"}]';
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
STEP=test
TAG=v9.9.9
NEW_VERSION=9.9.9
ROOT_DIR='${root.path}'
RESUME_TAG='$resumeTag'
REPO_SLUG=LibreKAT/Ocideck
FORGE_API=https://forge.invalid/api/v1
TOKEN_KEYCHAIN_SERVICE=test
DEPLOY_HOST=deploy.invalid
DEPLOY_URL=https://deploy.invalid
WEBSITE_URL=https://website.invalid/
TOKEN=test-token
MINISIGN_PW=${presetPassword ? 'test-password' : ''}
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() {
  local method="\$1" path="\$2"
  case "\$path" in
    '') return 0 ;;
    '/releases/tags/v9.9.9')
      ${sigState == 'absent' ? 'return 22' : "printf '%s\\n' '{\"id\":41}'"}
      ;;
    '/releases/41/assets') printf '%s\\n' '$assetsJson' ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
git() {
  case "\$*" in
    'ls-remote mirror refs/tags/v9.9.9 refs/tags/v9.9.9^{}')
      ${mirrorReachable ? (mirrorTag ? "printf 'deadbeef refs/tags/v9.9.9\\n'" : ':') : 'return 2'}
      ;;
    'ls-remote mirror') ${mirrorReachable ? 'return 0' : 'return 2'} ;;
    'ls-remote --exit-code origin refs/tags/v9.9.9')
      printf 'deadbeef refs/tags/v9.9.9\\n'; return 0 ;;
    *) return 0 ;;
  esac
}
ssh() { return 255; }
minisign() { return ${sigState == 'valid' ? 0 : 1}; }
make() {
  case "\$1" in
    sign-release) ${keyWorks ? ': >"\${2#SHA256SUMS=}.minisig"' : 'return 2'} ;;
    *) return 2 ;;
  esac
}
curl() {
  local out='' url='' previous='' arg
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ]; then out="\$arg"; fi
    previous="\$arg"; url="\$arg"
  done
  case "\$url" in
    */version.json)
      ${liveDemo ? "printf '%s\\n' '{\"version\":\"9.9.9\"}'" : "printf '%s\\n' '{\"version\":\"9.9.8\"}'"}
      ;;
    */SHA256SUMS.minisig) printf 'signature\\n' >"\$out" ;;
    */SHA256SUMS) printf 'manifest\\n' >"\$out" ;;
    *) return 22 ;;
  esac
}
preflight </dev/null
printf 'DOOR\\n'
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  test(
    '--resume met live demo en geldige handtekening vraagt geen deploy-SSH of sleutel',
    () {
      // deploy-SSH sterft (return 255), sign-release produceert niets en de
      // loze mirror-check faalt — alles wat nog nodig is, is er toch.
      final r = runPreflight();
      final output = '${r.stdout}\n${r.stderr}';
      expect(r.exitCode, 0, reason: output);
      expect(output, contains('overgeslagen'));
    },
    skip: skipOnWindows,
  );

  test('website-only resume vraagt zonder stdin geen minisign-wachtwoord', () {
    final r = runPreflight(presetPassword: false);
    final output = '${r.stdout}\n${r.stderr}';

    expect(r.exitCode, 0, reason: output);
    expect(output, isNot(contains('Wachtwoord')));
    expect(output, isNot(contains('leeg wachtwoord')));
    expect(output, contains('DOOR'));
  }, skip: skipOnWindows);

  test('--resume met achterlopende demo eist wél een werkende deploy-host', () {
    final r = runPreflight(liveDemo: false);
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('deploy-host'));
  }, skip: skipOnWindows);

  test('--resume zonder geldige handtekening eist de minisign-sleutel', () {
    final r = runPreflight(sigState: 'missing');
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('minisign proef-tekening faalde'));
  }, skip: skipOnWindows);

  test('--resume met ontbrekende mirror-tag eist een bereikbare mirror', () {
    final r = runPreflight(mirrorTag: false, mirrorReachable: false);
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('mirror'));
  }, skip: skipOnWindows);

  test('een verse release (geen --resume) toets álle capaciteiten', () {
    final r = runPreflight(resumeTag: '', deployReachable: false);
    final output = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: output);
    expect(output, contains('deploy-host'));
  }, skip: skipOnWindows);
}
