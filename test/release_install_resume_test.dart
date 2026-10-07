import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressie voor #2304: de lokale /Applications-wissel was niet hervatbaar.
///
/// PENDING_APP leefde alleen in de procesvariabele van de verse run. Faalde de
/// installatiewissel na een complete publieke release, dan startte --resume met
/// een lege PENDING_APP, sloeg de installatie stil over en meldde toch "klaar".
/// Nu herontdekt finish de bij de tag horende build, verifieert versie en zegel
/// vóór installatie, en meldt de lokale stap expliciet OPEN als er niets
/// bruikbaars is.
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

  /// Bouwt een minimaal .app-skelet met de gegeven bundelversie; PlistBuddy is
  /// een echte binary die de Info.plist gewoon leest.
  String fakeApp(Directory state, {String version = '9.9.9'}) {
    final app = Directory(
      '${state.path}/build/macos/Build/Products/Release/OciDeck.app/Contents',
    )..createSync(recursive: true);
    File('${app.path}/Info.plist').writeAsStringSync(
      '<?xml version="1.0"?>\n<plist version="1.0"><dict>\n'
      '<key>CFBundleShortVersionString</key><string>$version</string>\n'
      '</dict></plist>\n',
    );
    return app.parent.path;
  }

  ProcessResult runFinish(String mocksAndCall) {
    final dir = Directory.systemTemp.createTempSync('ocideck-install-');
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
RUN_T0=\$(date +%s)
${allFunctionDefinitions()}
$mocksAndCall
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  // Het vaste harnas voor finish(): logging zichtbaar, de installatiewissel
  // zelf gelogd naar een traceerbaar bestand, git zo dat de branchherstel-
  // helpers vroeg terugkeren (resume-pad: BRANCH_OWNED=0, HEAD op een tak).
  String finishHarness({
    required Directory state,
    required String extra,
    String pendingApp = '',
    int skipInstall = 0,
  }) {
    return '''
STATE=${state.path}
INSTALL_TRACE=\$STATE/install.trace
APPLICATIONS_DIR=\$STATE/Applications
BRANCH=release/v9.9.9
START_BRANCH=main
BRANCH_OWNED=0
PENDING_APP='$pendingApp'
SKIP_INSTALL=$skipInstall
read_token() { :; }
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
git() {
  case "\$*" in
    'rev-parse --abbrev-ref HEAD') printf 'main\\n' ;;
    *) return 1 ;;
  esac
}
codesign() { return 0; }
install_macos_app() { printf '%s\\n' "\$1" >>"\$INSTALL_TRACE"; return 0; }
cd "\$STATE"
$extra
''';
  }

  test(
    '--resume probeert de installatie opnieuw met de herontdekte tag-build',
    () {
      // Eerste run: de publieke release rondde af, de installatiewissel faalde.
      // Het proces is weg — PENDING_APP leeg — maar de genotariseerde build
      // ligt nog in de bouwmap. --resume moet die vinden en installeren.
      final state = Directory.systemTemp.createTempSync('ocideck-install-');
      addTearDown(() => state.deleteSync(recursive: true));
      final app = fakeApp(state);
      final result = runFinish(finishHarness(state: state, extra: 'finish'));
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      final trace = File('${state.path}/install.trace');
      expect(
        trace.existsSync() ? trace.readAsStringSync().trim() : '',
        endsWith('build/macos/Build/Products/Release/OciDeck.app'),
        reason:
            'de herontdekte build ($app) moet opnieuw geïnstalleerd worden.'
            '\n$output',
      );
      expect(output, contains('vervangen door de uitgebrachte'));
      expect(output, contains('Lokale installatie'));
      expect(output, isNot(contains('NOG OPEN')), reason: output);
    },
    skip: skipOnWindows,
  );

  test(
    '--resume meldt de lokale installatie expliciet open zonder bruikbare build',
    () {
      final state = Directory.systemTemp.createTempSync('ocideck-install-');
      addTearDown(() => state.deleteSync(recursive: true));
      final result = runFinish(finishHarness(state: state, extra: 'finish'));
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(
        output,
        contains('NOG OPEN'),
        reason: 'zonder build mag geen stil succes volgen.\n$output',
      );
      expect(
        output,
        contains('ocideck-macos-9.9.9.zip'),
        reason: 'de melding wijst naar de gepubliceerde build.\n$output',
      );
      expect(
        File('${state.path}/install.trace').existsSync(),
        isFalse,
        reason: 'er was niets bruikbaars om te installeren.\n$output',
      );
    },
    skip: skipOnWindows,
  );

  test(
    'een build van een andere versie wordt niet als deze release geïnstalleerd',
    () {
      final state = Directory.systemTemp.createTempSync('ocideck-install-');
      addTearDown(() => state.deleteSync(recursive: true));
      fakeApp(state, version: '9.9.8');
      final result = runFinish(finishHarness(state: state, extra: 'finish'));
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('NOG OPEN'), reason: output);
      expect(
        File('${state.path}/install.trace').existsSync(),
        isFalse,
        reason: 'een build van v9.9.8 hoort niet bij deze tag.\n$output',
      );
    },
    skip: skipOnWindows,
  );

  test('--skip-install blijft de enige bewuste manier om over te slaan', () {
    final state = Directory.systemTemp.createTempSync('ocideck-install-');
    addTearDown(() => state.deleteSync(recursive: true));
    fakeApp(state);
    final result = runFinish(
      finishHarness(state: state, skipInstall: 1, extra: 'finish'),
    );
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('bewust overgeslagen (--skip-install)'));
    expect(
      File('${state.path}/install.trace').existsSync(),
      isFalse,
      reason: output,
    );
  }, skip: skipOnWindows);

  test('een verse run installeert PENDING_APP na verificatie', () {
    final state = Directory.systemTemp.createTempSync('ocideck-install-');
    addTearDown(() => state.deleteSync(recursive: true));
    final app = fakeApp(state);
    final result = runFinish(
      finishHarness(state: state, pendingApp: app, extra: 'finish'),
    );
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(
      File('${state.path}/install.trace').readAsStringSync().trim(),
      app,
      reason: output,
    );
  }, skip: skipOnWindows);

  test(
    'een PENDING_APP die geen geverifieerde tag-build is, wordt geweigerd',
    () {
      final state = Directory.systemTemp.createTempSync('ocideck-install-');
      addTearDown(() => state.deleteSync(recursive: true));
      final app = fakeApp(state, version: '9.9.8');
      final result = runFinish(
        finishHarness(state: state, pendingApp: app, extra: 'finish'),
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        result.exitCode,
        isNot(0),
        reason:
            'een afwijkende build mag nooit als deze release installeren.'
            '\n$output',
      );
      expect(
        File('${state.path}/install.trace').existsSync(),
        isFalse,
        reason: output,
      );
    },
    skip: skipOnWindows,
  );
}
