@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt #2297: vanaf de eerste remote tagpushpoging is de toestand
/// remote-onzeker. Verdwijnt het antwoord óf de teruglezing, dan kan de tag er
/// al staan — de lokale release-branch is dan herstelmateriaal en de enige
/// route is read-only controleren en DEZELFDE tag hervatten. Alleen een
/// aantoonbaar afgewezen push mag nog als "niets gebeurd" gelden.
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

  /// Draait [call] met gemockte git. [pushRc] is de exit van de tagpush;
  /// [lsAfter] stuurt de teruglezing ná de push: `landed`, `absent`
  /// (aantoonbaar weg) of `fail` (onleesbaar). De eerste ls-remote — vóór de
  /// push — rapporteert altijd absent.
  /// Geeft (resultaat, git-aanroepen) terug.
  (ProcessResult, List<String>) runTagPush({
    int pushRc = 0,
    String lsAfter = 'landed',
    String call = 'tag_and_push deadbeef',
  }) {
    final dir = Directory.systemTemp.createTempSync('tag-uncertain-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gitcalls = File('${dir.path}/gitcalls.log');
    final counter = File('${dir.path}/ls-count');
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
${allFunctionDefinitions()}
TAG=v9.9.9
NEW_VERSION=9.9.9
BRANCH=release/v9.9.9
TAG_PUSHED=0
TAG_UNCERTAIN=0
BRANCH_PUSHED=1
BRANCH_OWNED=1
START_BRANCH=main
CLEANUP_BACK=
ROOT_DIR=${Directory.current.path}
TMP=
STEP=test
GITCALLS=${gitcalls.path}
LSCOUNT=${counter.path}
LS_AFTER=$lsAfter
PUSH_RC=$pushRc
sleep() { :; }
git() {
  printf '%s\\n' "\$*" >> "\$GITCALLS"
  case "\$*" in
    'ls-remote origin refs/tags/v9.9.9 refs/tags/v9.9.9^{}')
      local n=0
      [ -f "\$LSCOUNT" ] && n=\$(cat "\$LSCOUNT")
      n=\$((n + 1)); printf '%s' "\$n" > "\$LSCOUNT"
      if [ "\$n" -le 1 ]; then
        return 0
      fi
      case "\$LS_AFTER" in
        landed) printf 'deadbeef refs/tags/v9.9.9^{}\\n' ;;
        absent) return 0 ;;
        fail) return 2 ;;
      esac ;;
    'fetch --quiet origin') return 0 ;;
    'cat-file -e deadbeef^{commit}') return 0 ;;
    'show deadbeef:pubspec.yaml') printf 'version: 9.9.9\\n' ;;
    'tag -d v9.9.9') return 0 ;;
    'tag -a v9.9.9 -m OciDeck v9.9.9 deadbeef') return 0 ;;
    'rev-list -n 1 v9.9.9') printf 'deadbeef\\n' ;;
    'push --quiet origin v9.9.9') return "\$PUSH_RC" ;;
    'remote get-url mirror') return 1 ;;
    'rev-parse -q --verify refs/heads/release/v9.9.9') return 0 ;;
    'checkout --quiet main') return 0 ;;
    'branch -D release/v9.9.9') return 0 ;;
    'restore --staged --worktree --'*) return 0 ;;
    'clean -fd -- sbom') return 0 ;;
    *) printf 'git onverwacht: %s\\n' "\$*" >&2; return 9 ;;
  esac
}
trap - ERR
$call
printf 'DOOR\\n'
''');
    final result = Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
    final calls = gitcalls.existsSync()
        ? gitcalls.readAsLinesSync()
        : <String>[];
    return (result, calls);
  }

  test('verloren antwoord ná een mogelijk gelande push: branch blijft, '
      'herstelroute is dezelfde tag', () {
    final (result, calls) = runTagPush(pushRc: 1, lsAfter: 'fail');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(output, contains('--resume v9.9.9'));
    expect(output, contains('--status v9.9.9'));
    expect(
      calls,
      isNot(contains('branch -D release/v9.9.9')),
      reason:
          'bij een remote-onzekere tag is de lokale branch herstel'
          'materiaal — opruimen mag nooit.',
    );
    expect(
      output,
      isNot(contains('draai het script opnieuw')),
      reason:
          'een verse release naast een mogelijk bestaande tag adviseren '
          'is precies de fout uit #2297.',
    );
  }, skip: skipOnWindows);

  test(
    'aantoonbaar afgewezen push: gewone verse-run-route en wél opruiming',
    () {
      final (result, calls) = runTagPush(pushRc: 1, lsAfter: 'absent');
      final output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0), reason: output);
      expect(output, contains('aantoonbaar afgewezen'));
      expect(calls, contains('branch -D release/v9.9.9'));
    },
    skip: skipOnWindows,
  );

  test('verloren antwoord, wél gelande tag: de teruglezing bewijst en de '
      'keten gaat door', () {
    final (result, calls) = runTagPush(pushRc: 1, lsAfter: 'landed');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('teruglezing bewijst'));
    expect(output, contains('DOOR'));
  }, skip: skipOnWindows);

  test('succes gemeld maar onleesbaar: óók onzeker, óók geen opruiming', () {
    final (result, calls) = runTagPush(pushRc: 0, lsAfter: 'fail');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(output, contains('--resume v9.9.9'));
    expect(calls, isNot(contains('branch -D release/v9.9.9')));
  }, skip: skipOnWindows);

  test('on_err noemt bij een onzekere tag alleen status + resume', () {
    final (result, calls) = runTagPush(call: 'on_err 42');
    // TAG_UNCERTAIN wordt in deze harness niet gezet — zet hem vóór de call.
    // De default hierboven is 0, dus overschrijven via een eigen call:
    final (result2, calls2) = runTagPush(call: 'TAG_UNCERTAIN=1; on_err 42');
    final output = '${result2.stdout}\n${result2.stderr}';
    expect(output, contains('--status v9.9.9'));
    expect(output, contains('--resume v9.9.9'));
    expect(output, isNot(contains('repareer het en draai het script opnieuw')));
    expect(calls2, isNot(contains('branch -D release/v9.9.9')));
    final output0 = '${result.stdout}\n${result.stderr}';
    // Zonder onzekerheid blijft het oude branch-hersteladvies bestaan.
    expect(output0, contains('--resume v9.9.9'));
    expect(calls, contains('branch -D release/v9.9.9'));
  }, skip: skipOnWindows);
}
