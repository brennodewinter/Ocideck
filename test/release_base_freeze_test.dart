@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt #2299: de servermerge mag alleen door als origin/main nog exact op
/// de gekeurde base staat. De releasebranch wordt vroeg van origin/main
/// getakt en daarna lokaal gebouwd en gekeurd; schuift main intussen door,
/// dan zou de getagde mergeboom base-commits bevatten die nooit in deze
/// keten keurden of bouwden. De toets is de merge-base — het vastgelegde
/// vertrekpunt — tegen de actuele main-tip.
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

  /// Draait merge_pr met gemockte api/git. [fakeBase] en [fakeMain] sturen de
  /// merge-base en de main-tip; [merged] simuleert een al gemergede PR.
  /// Geeft (resultaat, api-mutaties) terug.
  (ProcessResult, List<String>) runMerge({
    String fakeBase = 'ba5e1',
    String fakeMain = 'ba5e1',
    bool merged = false,
  }) {
    final dir = Directory.systemTemp.createTempSync('base-freeze-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mutations = File('${dir.path}/mutations.log');
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
${allFunctionDefinitions()}
TAG=v9.9.9
NEW_VERSION=9.9.9
BRANCH=release/v9.9.9
ROOT_DIR=${Directory.current.path}
FORGE_API=https://forge.invalid/api/v1
REPO_SLUG=LibreKAT/Ocideck
TOKEN=t
MUTATIONS=${mutations.path}
TMP=
STEP=test
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() {
  local method="\$1" path="\$2"
  if [ "\$method" != GET ]; then
    printf '%s %s\\n' "\$method" "\$path" >>"\$MUTATIONS"
  fi
  case "\$method \$path" in
    'GET /pulls?state=all&limit=100')
      printf '%s\\n' '[{"number":7,"state":"open","merged":$merged,"head":{"sha":"h","ref":"release/v9.9.9","label":"release/v9.9.9"},"merge_commit_sha":null,"title":"chore(release): versie 9.9.9"}]'
      ;;
    *) printf '%s\\n' '{}' ;;
  esac
}
git() {
  case "\$*" in
    'fetch origin main release/v9.9.9 --quiet') return 0 ;;
    'fetch origin main release/v9.9.9'* ) return 0 ;;
    'merge-base origin/release/v9.9.9 origin/main'*)
      [ -n "$fakeBase" ] && printf '%s\\n' "$fakeBase" || return 1 ;;
    'rev-parse origin/main'*)
      [ -n "$fakeMain" ] && printf '%s\\n' "$fakeMain" || return 1 ;;
    *) printf 'git onverwacht: %s\\n' "\$*" >&2; exit 9 ;;
  esac
}
merge_pr 7 deadbeef
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

  test('ongewijzigde base: de merge gaat door', () {
    final (result, calls) = runMerge();
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('base bevroren'));
    expect(calls, contains('POST /pulls/7/merge'));
  }, skip: skipOnWindows);

  test('doorgeschoven main: geen merge, geen tag, helder hersteladvies', () {
    final (result, calls) = runMerge(fakeMain: 'n3wer');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(output, contains('schoof door'));
    expect(output, contains('--resume v9.9.9'));
    expect(
      calls,
      isNot(contains('POST /pulls/7/merge')),
      reason:
          'een servermerge op een nieuwe base tagt een boom die nooit gekeurd '
          'is — die mag nooit gebeuren.',
    );
  }, skip: skipOnWindows);

  test('onleesbare base-toestand: onbekend is geen toestemming', () {
    final (result, calls) = runMerge(fakeBase: '');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(calls, isNot(contains('POST /pulls/7/merge')));
  }, skip: skipOnWindows);

  test('een al gemergede PR slaat de base-toets veilig over', () {
    final (result, calls) = runMerge(merged: true, fakeMain: 'n3wer');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('al gemerged'));
    expect(calls, isNot(contains('POST /pulls/7/merge')));
  }, skip: skipOnWindows);
}
