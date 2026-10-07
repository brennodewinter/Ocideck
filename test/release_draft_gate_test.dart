@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards #2311: a release stays a draft until every expected asset, the
/// Debian package AND a valid minisign signature are in place. The CI job
/// fills the release but never publishes; release_auto.sh flips draft→false
/// only after the signature verifies, and only then dispatches the
/// website-downloads workflow (it reads public URLs that do not exist while
/// the release is a draft).
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  final releaseYaml = File('.forgejo/workflows/release.yml').readAsStringSync();
  final siteYaml = File(
    '.forgejo/workflows/website-downloads.yml',
  ).readAsStringSync();
  final autoScript = File(script).readAsStringSync();

  group('de workflow houdt de release draft', () {
    test('publiceren maakt de release als draft aan', () {
      expect(releaseYaml, contains('draft:true'));
      expect(
        releaseYaml,
        isNot(contains('draft:false')),
        reason: 'een release.json met draft:false publiceert meteen — #2311.',
      );
    });

    test('de website-downloads-job staat niet meer in release.yml', () {
      expect(
        releaseYaml,
        isNot(contains(RegExp(r'^  website-downloads:', multiLine: true))),
        reason:
            'zolang de release draft is, kan de websitejob de publieke '
            'release-URL\'s niet lezen — hij hoort pas na publicatie.',
      );
      expect(siteYaml, contains('workflow_dispatch'));
      expect(siteYaml, contains('Website-downloads bijwerken'));
    });
  });

  group('release_auto publiceert pas na een geldige handtekening', () {
    test('fase 3 leest draft-assets via de API en publiceert met een PATCH', () {
      // Publieke download-URL's 404'en op een draft; het tekenstuk moet de
      // assets daarom met het token via browser_download_url lezen.
      expect(autoScript, contains('download_release_asset'));
      expect(autoScript, contains('-d \'{"draft":false}\''));
      expect(
        autoScript,
        contains('actions/workflows/website-downloads.yml/dispatches'),
        reason:
            'de website-workflow wordt door dezelfde stap gedispatcht, pas ná '
            'de publicatie.',
      );
    });
  });

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

  /// Draait de echte fase 3 met een gemockte forge/downloads/signer. Geeft het
  /// resultaat plus het mutatielogboek terug: elke niet-GET api()-call staat er
  /// in als "METHODE pad". [websiteRun] is de status van de nieuwste
  /// website-downloads-run op de tag ('' = geen run); [pageLive] bepaalt of de
  /// publieke downloadpagina al naar de tag wijst.
  (ProcessResult, List<String>) runPhase3({
    required bool signatureValid,
    String websiteRun = '',
    bool pageLive = true,
    bool resumedTempSignature = false,
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-draft-gate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final seen = pageLive ? '9.9.9' : '9.9.8';
    final page = File('${dir.path}/website.html')
      ..writeAsStringSync('''
<a href="https://forge.invalid/releases/download/v$seen/ocideck-linux-amd64-$seen.deb">deb</a>
<a href="https://forge.invalid/releases/download/v$seen/ocideck-linux-x86_64-$seen.AppImage">AppImage</a>
<a href="https://forge.invalid/releases/download/v$seen/ocideck-macos-$seen.zip">macOS</a>
<a href="https://forge.invalid/releases/download/v$seen/ocideck-windows-x64-setup-$seen.exe">Windows</a>
''');
    final mutations = File('${dir.path}/mutations.log');
    final tempRenamed = File('${dir.path}/temp-renamed');
    const tempName =
        'SHA256SUMS.minisig.new.'
        'e5bc2c58bbb0a51702ebe17973eaa4a28668b47457854fb917aa6d2fc45a39bd';
    const normalAssets =
        '[{"name":"ocideck-web-9.9.9.tar.gz"},{"name":"ocideck-linux-x64-9.9.9.tar.gz"},{"name":"ocideck-linux-amd64-9.9.9.deb"},{"name":"ocideck-linux-x86_64-9.9.9.rpm"},{"name":"ocideck-linux-x86_64-9.9.9.AppImage"},{"name":"ocideck-macos-9.9.9.zip"},{"name":"ocideck-windows-x64-9.9.9.zip"},{"name":"ocideck-windows-x64-setup-9.9.9.exe"},{"name":"ocideck-9.9.9.cdx.json"},{"name":"ocideck-9.9.9.spdx.json"},{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"},{"id":90,"name":"SHA256SUMS.minisig","browser_download_url":"https://dl.invalid/x/SHA256SUMS.minisig"}]';
    const tempAssets =
        '[{"name":"ocideck-web-9.9.9.tar.gz"},{"name":"ocideck-linux-x64-9.9.9.tar.gz"},{"name":"ocideck-linux-amd64-9.9.9.deb"},{"name":"ocideck-linux-x86_64-9.9.9.rpm"},{"name":"ocideck-linux-x86_64-9.9.9.AppImage"},{"name":"ocideck-macos-9.9.9.zip"},{"name":"ocideck-windows-x64-9.9.9.zip"},{"name":"ocideck-windows-x64-setup-9.9.9.exe"},{"name":"ocideck-9.9.9.cdx.json"},{"name":"ocideck-9.9.9.spdx.json"},{"name":"SHA256SUMS","browser_download_url":"https://dl.invalid/x/SHA256SUMS"},{"id":91,"name":"$tempName","browser_download_url":"https://dl.invalid/x/$tempName"}]';
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
MUTATIONS=${mutations.path}
TEMP_RENAMED=${tempRenamed.path}
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
minisign() { return ${signatureValid ? 0 : 1}; }
api() {
  local method="\$1" path="\$2"
  if [ "\$method" != GET ]; then
    printf '%s %s\\n' "\$method" "\$path" >>"\$MUTATIONS"
  fi
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
    'GET /releases/tags/v9.9.9') printf '%s\\n' '{"id":41,"draft":true}' ;;
    'GET /releases/41/assets')
      if ${resumedTempSignature ? 'true' : 'false'}; then
        if [ -f "\$TEMP_RENAMED" ]; then
          printf '%s\\n' '$normalAssets'
        else
          printf '%s\\n' '$tempAssets'
        fi
      else
        printf '%s\\n' '$normalAssets'
      fi
      ;;
    'PATCH /releases/41/assets/91') : >"\$TEMP_RENAMED"; printf '%s\\n' '{}' ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
curl() {
  local out='' url='' previous='' arg authorized=0
  for arg in "\$@"; do
    if [ "\$previous" = '-o' ]; then out="\$arg"; fi
    [ "\$arg" = 'Authorization: token test-token' ] && authorized=1
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
    */SHA256SUMS.minisig.new.*)
      [ "\$authorized" -eq 1 ] || return 22
      printf 'signature\\n' >"\$out"
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
    final result = Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
    final calls = mutations.existsSync()
        ? mutations.readAsLinesSync()
        : <String>[];
    return (result, calls);
  }

  test('geldige handtekening: publiceren + website-dispatch', () {
    final (result, calls) = runPhase3(signatureValid: true);
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(
      calls,
      contains('PATCH /releases/41'),
      reason: 'de release moet expliciet van draft naar publiek (#2311).',
    );
    expect(
      calls,
      contains('POST /actions/workflows/website-downloads.yml/dispatches'),
      reason: 'de website-update hoort pas ná de publicatie te lopen.',
    );
    // De publish-PATCH komt ná elke asset-mutatie: een POST op assets is een
    // schrijver, de PATCH op de release zelf is de laatste stap.
    expect(
      calls.indexOf('PATCH /releases/41'),
      greaterThan(calls.indexWhere((c) => c.startsWith('POST /releases/'))),
      reason: 'de release mag pas publiek nadat de handtekening eraan hangt.',
    );
  }, skip: skipOnWindows);

  test('resume leest een tijdelijke draft-handtekening geauthenticeerd', () {
    final (result, calls) = runPhase3(
      signatureValid: true,
      resumedTempSignature: true,
    );
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('tijdelijke handtekening hervat'));
    expect(
      calls.where((call) => call.startsWith('POST /releases/41/assets')),
      isEmpty,
      reason: 'de reeds geüploade tijdelijke handtekening hoort hergebruikt.',
    );
  }, skip: skipOnWindows);

  test(
    'ongeldige handtekening: geen PATCH, geen dispatch — de release blijft draft',
    () {
      final (result, calls) = runPhase3(signatureValid: false);
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0), reason: output);
      expect(
        calls,
        isNot(contains('PATCH /releases/41')),
        reason:
            'een release waarvan de handtekening niet verifieert mag nooit '
            'publiek worden — iedere fout laat hem als draft staan (#2311).',
      );
      expect(
        calls,
        isNot(
          contains('POST /actions/workflows/website-downloads.yml/dispatches'),
        ),
      );
    },
    skip: skipOnWindows,
  );

  group('de externe website-deploy wordt afzonderlijk gevolgd (#2302)', () {
    const dispatch = 'POST /actions/workflows/website-downloads.yml/dispatches';

    test('een nog actieve externe deploy krijgt geen tweede publicatie', () {
      final (result, calls) = runPhase3(
        signatureValid: true,
        websiteRun: 'in_progress',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('geen tweede publicatie'));
      expect(
        calls,
        isNot(contains(dispatch)),
        reason:
            'zolang de eerste externe deploy actief kan zijn start er geen '
            'tweede publicatie — dat is een tweede schrijver.',
      );
      expect(
        calls,
        contains('PATCH /releases/41'),
        reason:
            'een actieve website-deploy mag de releasepublicatie niet '
            'terugdraaien.',
      );
    }, skip: skipOnWindows);

    test(
      'stale pagina + lopende deploy: géén host-beschuldiging, géén dispatch',
      () {
        final (result, calls) = runPhase3(
          signatureValid: true,
          websiteRun: 'in_progress',
          pageLive: false,
        );
        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNot(0), reason: output);
        expect(output, contains('loopt nog'));
        expect(
          output,
          isNot(contains('naar welke host')),
          reason:
              'een nog lopende of onbekende externe deploy wordt nooit als '
              'verkeerde host gepresenteerd.',
        );
        expect(calls, isNot(contains(dispatch)));
      },
      skip: skipOnWindows,
    );

    test(
      'stale pagina + gefaalde deploy: faalrapport en handmatige fallback',
      () {
        final (result, calls) = runPhase3(
          signatureValid: true,
          websiteRun: 'failure',
          pageLive: false,
        );
        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNot(0), reason: output);
        expect(output, contains('website-downloads-run faalde'));
        expect(output, contains('publiceersite'));
        expect(
          calls,
          contains('PATCH /releases/41'),
          reason:
              'een rode website-sync blokkeert het tekenen en publiceren van de '
              'release niet — hij verhindert alleen het klaar melden.',
        );
      },
      skip: skipOnWindows,
    );

    test(
      'stale pagina + groene run: pas dan is de host/DNS-route de conclusie',
      () {
        final (result, calls) = runPhase3(
          signatureValid: true,
          websiteRun: 'success',
          pageLive: false,
        );
        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNot(0), reason: output);
        expect(output, contains('naar welke host'));
        expect(calls, isNot(contains(dispatch)));
      },
      skip: skipOnWindows,
    );
  });
}
