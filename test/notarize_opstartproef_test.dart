import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressies voor de opstartproef in `scripts/notarize_macos.sh`.
///
/// De echte bashfuncties draaien in een hermetisch harnas met een stub-app en
/// nagebootste `ioreg`-uitvoer; alleen die twee grenzen zijn gemockt.
///
/// Waarom deze test bestaat: de macOS-releasejob van v0.6.7 keurde een
/// getekende, genotariseerde en kerngezonde app af. De app kwam op en sloot
/// binnen zes seconden netjes af met exit 0, omdat het scherm van de bouw-Mac
/// op slot zat. `launchctl managername` blijft dan gewoon `Aqua`, dus de
/// sessiecheck zag het verschil niet — en de hele release-keten viel stil.
///
/// De proef mag daar niet meer op omvallen, maar moet wél blijven doen
/// waarvoor ze bestaat: een dyld- of hardened-runtime-weigering tegenhouden
/// (v0.6.4, en de PDFium-casing van #2115). Die twee eisen trekken tegen
/// elkaar, en juist daarom staan alle vier de takken hieronder.
void main() {
  const script = 'scripts/notarize_macos.sh';
  final skipOnWindows = Platform.isWindows
      ? 'notarize_macos.sh draait alleen op macOS, niet onder Windows Git Bash'
      : null;

  /// Alle top-level functiedefinities uit het échte script. Een kopie van de
  /// regels hier zou meegroeien met niets: dan toetst de test zichzelf.
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

  /// Een nep-`OciDeck`-binary met opgegeven gedrag, in een .app-structuur.
  String stubApp(Directory dir, String naam, String gedrag) {
    final app = Directory('${dir.path}/$naam.app/Contents/MacOS')
      ..createSync(recursive: true);
    final bin = File('${app.path}/OciDeck');
    bin.writeAsStringSync('#!/bin/sh\n$gedrag\n');
    Process.runSync('chmod', ['+x', bin.path]);
    return '${dir.path}/$naam.app';
  }

  /// De sessiestatus zoals `ioreg -n Root -d1 -a` hem op een Mac teruggeeft.
  String ioregPlist({required bool vergrendeld}) =>
      '<key>IOConsoleUsers</key><array><dict>\n'
      '${vergrendeld ? '<key>CGSSessionScreenIsLocked</key><true/>\n' : ''}'
      '<key>kCGSSessionOnConsoleKey</key><true/>\n'
      '</dict></array>\n';

  ProcessResult runProbe({required String gedrag, required bool vergrendeld}) {
    final dir = Directory.systemTemp.createTempSync('ocideck-opstartproef-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app = stubApp(dir, 'Stub', gedrag);
    final plist = File('${dir.path}/ioreg.plist')
      ..writeAsStringSync(ioregPlist(vergrendeld: vergrendeld));

    // De echte functies, met alleen ioreg omgeleid naar de nagebootste plist.
    final functies = allFunctionDefinitions().replaceAll(
      'ioreg -n Root -d1 -a 2>/dev/null',
      'cat "${plist.path}"',
    );
    final harness = File('${dir.path}/harness.sh');
    harness.writeAsStringSync('''
set -uo pipefail
APP='$app'
OCIDECK_PROBE_SECONDEN=1
export OCIDECK_PROBE_SECONDEN
section() { printf '== %s ==\\n' "\$1"; }
launchctl() { printf 'Aqua\\n'; }
$functies
opstartproef
''');
    return Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
  }

  group('opstartproef', () {
    test('een app die blijft draaien komt door de proef', () {
      final r = runProbe(gedrag: 'sleep 30', vergrendeld: false);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('in orde'));
    }, skip: skipOnWindows);

    test('een dyld-weigering blijft hard rood', () {
      final r = runProbe(
        gedrag:
            'echo "dyld: Library not loaded: @rpath/PDFium.framework/PDFium"'
            ' >&2; exit 3',
        vergrendeld: false,
      );
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('exit 3'));
      expect(r.stderr, contains('Library not loaded'));
      // Een laadfout mag nooit als sessieprobleem worden weggeschreven.
      expect(r.stdout, isNot(contains('overgeslagen')));
      expect(r.stderr, isNot(contains('overgeslagen')));
    }, skip: skipOnWindows);

    test('exit 0 bij een vergrendeld scherm wordt overgeslagen, niet rood', () {
      final r = runProbe(gedrag: 'exit 0', vergrendeld: true);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('overgeslagen'));
    }, skip: skipOnWindows);

    test(
      'exit 0 met een bruikbare sessie is alsnog rood, na twee pogingen',
      () {
        final r = runProbe(gedrag: 'exit 0', vergrendeld: false);
        expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
        expect(r.stderr, contains('poging 1'));
        expect(r.stderr, contains('poging 2'));
        expect(r.stderr, contains('tweemaal'));
      },
      skip: skipOnWindows,
    );
  });
}
