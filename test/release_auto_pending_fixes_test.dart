import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De poort op bekend herstelwerk in `scripts/release_auto.sh` (#2115).
///
/// v0.6.5 ging uit terwijl `fix/pdfium-framework-casing` al op origin stond en
/// niemand dat zag. De keten weigert nu te starten zolang er open issues of
/// PR's met het label `release-blocker` zijn, of `fix/*`-takken op origin
/// waarvan de kop niet in `origin/main` zit. De echte bashfuncties draaien
/// hier met gemockte `git` en `api`, zodat de toets geen forge of netwerk
/// nodig heeft.
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

  /// [branches] zijn `sha naam`-paren zoals `git ls-remote --heads` ze geeft;
  /// [mergedShas] zijn de koppen die de nep-`merge-base` als voorouder van
  /// main erkent. [blockers] is het JSON-antwoord van de issues-API.
  ProcessResult run({
    List<String> branches = const [],
    Set<String> mergedShas = const {},
    String blockers = '[]',
    bool ignoreFixes = false,
    String resumeTag = '',
  }) {
    final dir = Directory.systemTemp.createTempSync('ocideck-pending-fixes-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final branchLines = branches.map((b) => 'refs/heads/${b.split(' ')[1]}');
    final lsRemote = [
      for (var i = 0; i < branches.length; i++)
        '${branches[i].split(' ')[0]}\t${branchLines.elementAt(i)}',
    ].join('\n');
    final merged = mergedShas.map((s) => '"$s"').join('|');
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
STEP=test
RESUME_TAG='$resumeTag'
IGNORE_FIXES=${ignoreFixes ? 1 : 0}
${allFunctionDefinitions()}
log() { printf '%s\\n' "\$1"; }
section() { printf '== %s ==\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
git() {
  case "\$1" in
    fetch) return 0 ;;
    ls-remote) printf '%s\\n' '$lsRemote' ;;
    merge-base) case "\$3" in ${merged.isEmpty ? '""' : merged}) return 0 ;; *) return 1 ;; esac ;;
    *) echo "onverwachte git-aanroep: \$*" >&2; return 2 ;;
  esac
}
api() { printf '%s\\n' '$blockers'; }
assert_no_pending_fixes
echo "doorgelaten"
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('niets open en niets ongemerged: stil door', () {
    final r = run(branches: ['aaa fix/oud'], mergedShas: {'aaa'});
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, 'doorgelaten\n');
  }, skip: skipOnWindows);

  test('een fix/*-tak buiten main stopt de keten en wordt genoemd', () {
    final r = run(
      branches: ['aaa fix/oud', 'bbb fix/pdfium-framework-casing'],
      mergedShas: {'aaa'},
    );
    expect(r.exitCode, 1);
    expect(r.stdout, contains('fix/pdfium-framework-casing'));
    expect(r.stdout, isNot(contains('fix/oud')));
    expect(r.stderr, contains('DIE:'));
    expect(r.stderr, contains('--ondanks-fixes'));
  }, skip: skipOnWindows);

  test('een open release-blocker stopt de keten, ook zonder fix-tak', () {
    final r = run(
      blockers: '[{"number":2115,"title":"macOS 27: 0.6.4 start niet"}]',
    );
    expect(r.exitCode, 1);
    expect(r.stdout, contains('#2115 macOS 27: 0.6.4 start niet'));
    expect(r.stderr, contains('DIE:'));
  }, skip: skipOnWindows);

  test('--ondanks-fixes laat door, maar zet de keuze in het log', () {
    final r = run(
      branches: ['bbb fix/pdfium-framework-casing'],
      blockers: '[{"number":2115,"title":"blokkeert"}]',
      ignoreFixes: true,
    );
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, contains('fix/pdfium-framework-casing'));
    expect(r.stdout, contains('#2115 blokkeert'));
    expect(r.stdout, contains('--ondanks-fixes'));
    expect(r.stdout, endsWith('doorgelaten\n'));
  }, skip: skipOnWindows);

  test('--resume kijkt er niet naar: de inhoud van die release ligt vast', () {
    final r = run(
      branches: ['bbb fix/pdfium-framework-casing'],
      blockers: '[{"number":2115,"title":"blokkeert"}]',
      resumeTag: 'v9.9.9',
    );
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, 'doorgelaten\n');
  }, skip: skipOnWindows);
}
