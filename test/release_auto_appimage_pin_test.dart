import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressies voor #2324: de pre-flight toetst de appimagetool-pin
/// tegen de officiële GitHub asset-digest vóór elke branch/tagmutatie. Een
/// verplaatste rollende `continuous`-asset brak v0.6.14 pas ná de tag
/// (release-run 5479, job 23681).
///
/// De echte bashfuncties draaien in een hermetisch harnas; `curl` en `git`
/// (ls-remote) zijn gemockt, de pin komt uit een fixture-workflow.
void main() {
  const script = 'scripts/release_auto.sh';
  const pinnedSha =
      'a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0';
  const upstreamSha =
      '95cbe7cce9717fce90c484e34052ee7c7f1d7635b33c12525b4776826a7d29b6';
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

  ProcessResult runHarness(String body) {
    final dir = Directory.systemTemp.createTempSync('ocideck-appimage-pin-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
STEP=test
RESUME_TAG=""
SELF_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
OCIDECK_APPIMAGE_WORKFLOW="\$SELF_DIR/wf.yml"
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
$body
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  const writeFixture = r'''
cat >"$OCIDECK_APPIMAGE_WORKFLOW" <<'YAML'
      - name: Linux-pakketten bouwen (AppImage/.deb/.rpm)
        env:
          APPIMAGETOOL_URL: https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
          APPIMAGETOOL_SHA256: __SHA__
YAML
''';

  String fixtureWith(String sha) => writeFixture.replaceAll('__SHA__', sha);

  const curlOk = r'''
curl() {
  case "$*" in
    *api.github.com*releases/tags/continuous*)
      printf '%s\n' '{"assets":[{"name":"appimagetool-x86_64.AppImage","digest":"sha256:__SHA__"}]}'
      ;;
    *) return 1 ;;
  esac
}
''';

  String curlReturning(String sha) => curlOk.replaceAll('__SHA__', sha);

  test('een kloppende pin is groen', () {
    final result = runHarness('''
${fixtureWith(pinnedSha)}
${curlReturning(pinnedSha)}
assert_appimagetool_pin
echo KLAAR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('appimagetool-pin klopt'));
    expect(output, contains('KLAAR'));
  }, skip: skipOnWindows);

  test('een verouderde pin blokkeert vóór de tag met een herstelcommando', () {
    final result = runHarness('''
${fixtureWith(pinnedSha)}
${curlReturning(upstreamSha)}
assert_appimagetool_pin
echo DOOR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(output, contains('verouderd'));
    expect(output, contains(pinnedSha));
    expect(output, contains(upstreamSha));
    expect(
      output,
      contains('APPIMAGETOOL_SHA256: $upstreamSha'),
      reason: 'het herstelcommando noemt de nieuwe pin expliciet',
    );
    expect(output, contains('Niets gemuteerd'));
    expect(output, isNot(contains('DOOR')));
  }, skip: skipOnWindows);

  test('een onleesbare GitHub-API is onbekend, niet afwezig', () {
    final result = runHarness('''
${fixtureWith(pinnedSha)}
curl() { return 1; }
assert_appimagetool_pin
echo DOOR
''');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('onbekend, niet afwezig'));
    expect(result.stderr, isNot(contains('DOOR')));
  }, skip: skipOnWindows);

  test('een antwoord zonder digest-veld is onbekend, niet groen', () {
    final result = runHarness('''
${fixtureWith(pinnedSha)}
curl() {
  printf '%s\n' '{"assets":[{"name":"appimagetool-x86_64.AppImage"}]}'
}
assert_appimagetool_pin
echo DOOR
''');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('onbekend'));
    expect(result.stderr, isNot(contains('DOOR')));
  }, skip: skipOnWindows);

  test('een ontbrekend pinbestand faalt hoorbaar', () {
    final result = runHarness('''
rm -f "\$OCIDECK_APPIMAGE_WORKFLOW"
curl() { return 1; }
assert_appimagetool_pin
echo DOOR
''');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('niet leesbaar'));
  }, skip: skipOnWindows);

  test('bij --resume met gepushte tag is een mismatch een waarschuwing', () {
    // De tag staat er al: er is geen mutatie meer om vóór te blokkeren en de
    // lopende keten gebruikt de pin van de tag-commit. Blokkeren zou de
    // herstelroute zelf onbruikbaar maken.
    final result = runHarness('''
${fixtureWith(pinnedSha)}
${curlReturning(upstreamSha)}
RESUME_TAG=v9.9.9
git() { return 0; }
assert_appimagetool_pin
echo KLAAR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('wijkt af'));
    expect(output, contains('KLAAR'));
  }, skip: skipOnWindows);

  test('bij --resume zónder gepushte tag blokkeert een mismatch alsnog', () {
    final result = runHarness('''
${fixtureWith(pinnedSha)}
${curlReturning(upstreamSha)}
RESUME_TAG=v9.9.9
git() { return 2; }
assert_appimagetool_pin
echo DOOR
''');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('verouderd'));
  }, skip: skipOnWindows);

  test('de env-override deelt het pincontract met package_linux.sh', () {
    final result = runHarness('''
${curlReturning(pinnedSha)}
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="$pinnedSha"
rm -f "\$OCIDECK_APPIMAGE_WORKFLOW"
assert_appimagetool_pin
echo KLAAR
''');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('KLAAR'));
  }, skip: skipOnWindows);
}
