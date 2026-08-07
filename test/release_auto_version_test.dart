import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_version_bump.dart';

/// De guard-toets voor `scripts/release_auto.sh` (#1161).
///
/// Het onbewaakte release-script berekent de volgende versie uit een menukeuze
/// (patch/minor/major) i.p.v. een meegegeven tag. Die berekening ÍS de tag-guard:
/// ze mag alléén een canonieke één-as-stap opleveren — precies de regel die
/// [legalNextVersions] vastlegt en die `make check-version-bump` op de PR
/// afdwingt. Deze test pint dat de bash-rekenkunde en de Dart-regel niet uit
/// elkaar kunnen lopen.
///
/// De `--print-version`-modus is bewust hermetisch (leest alleen `pubspec.yaml`,
/// raakt git noch netwerk), zodat deze test snel en zonder poort-neveneffecten
/// draait.
void main() {
  const script = 'scripts/release_auto.sh';

  // release_auto.sh is een macOS/Unix-maintainertool: hij leunt op de
  // macOS-keychain (`security`), op `codesign`/`ditto` en op `/Applications`, en
  // wordt alleen op de maintainer-Mac en de Linux-CI gedraaid. Onder Windows
  // Git Bash (alleen de mirror-CI, alleen op een v*-tag) viel het script om met
  // exit 1 terwijl macOS/Linux — waar de release écht draait — groen waren. Sla
  // deze bash-toetsen op Windows over i.p.v. een niet-ondersteund draaipunt te
  // toetsen; de Forgejo-poorten die merges gate'n draaien geen Windows.
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  String currentPubspecVersion() {
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      final m = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      ).firstMatch(line);
      if (m != null) return m.group(1)!;
    }
    fail('geen version: in pubspec.yaml');
  }

  String printVersion(String level) {
    final r = Process.runSync('bash', [script, '--print-version', level]);
    expect(
      r.exitCode,
      0,
      reason: 'release_auto.sh --print-version $level faalde: ${r.stderr}',
    );
    return (r.stdout as String).trim();
  }

  test(
    'de drie niveaus zijn exact de canonieke bumps van de huidige versie',
    () {
      final current = SemVer.tryParse(currentPubspecVersion())!;
      final patch = printVersion('patch');
      final minor = printVersion('minor');
      final major = printVersion('major');

      // 'v'-prefix eraf; de guard rekent op de kale semver.
      final produced = {
        patch.substring(1),
        minor.substring(1),
        major.substring(1),
      };
      expect(patch, startsWith('v'));
      expect(
        produced,
        legalNextVersions(current),
        reason: 'de menu-rekenkunde wijkt af van de canonieke één-as-regel',
      );
    },
    skip: skipOnWindows,
  );

  test('elk niveau kiest de juiste as', () {
    final current = SemVer.tryParse(currentPubspecVersion())!;
    expect(
      printVersion('patch'),
      'v${current.major}.${current.minor}.${current.patch + 1}',
    );
    expect(printVersion('minor'), 'v${current.major}.${current.minor + 1}.0');
    expect(printVersion('major'), 'v${current.major + 1}.0.0');
  }, skip: skipOnWindows);

  test('zonder niveau weigert --print-version', () {
    final r = Process.runSync('bash', [script, '--print-version']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('niveau'));
  }, skip: skipOnWindows);

  // --resume (#9): al deze paden falen hermetisch — vóór git/netwerk — zodat de
  // test snel en zonder poort-neveneffecten blijft.
  test('--resume zonder tag weigert', () {
    final r = Process.runSync('bash', [script, '--resume']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('tag'));
  }, skip: skipOnWindows);

  test('een losse tag zonder --resume weigert (typfout-vangnet)', () {
    final r = Process.runSync('bash', [script, 'v9.9.9']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('resume'));
  }, skip: skipOnWindows);
}
