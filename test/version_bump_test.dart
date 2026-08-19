import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_version_bump.dart';

/// The version was once bumped 0.2.0 → 1.2.1 in a release commit and tagged
/// before anyone caught it. `make check-static` now runs
/// tool/check_version_bump.dart on every PR to refuse a bump that isn't a
/// single canonical semver step. This pins the rule that gate enforces.
///
/// The [SemVer] parser and [legalNextVersions]/[isLegalTransition] are pure and
/// git-free, so the transition rule is tested directly here; the tool's I/O
/// half (reading pubspec, asking git for the last tag) is exercised by the gate
/// itself under `make check`.
void main() {
  group('legalNextVersions', () {
    test('from 0.2.0 allows exactly patch, minor and major — not 1.2.1', () {
      // The regression: 0.2.0 → 1.2.1 must be impossible to reach as a legal
      // step. The only three legal successors carry a single axis forward.
      expect(legalNextVersions(const SemVer(0, 2, 0)), {
        '0.2.1',
        '0.3.0',
        '1.0.0',
      });
    });

    test('a major bump zeroes minor and patch', () {
      expect(legalNextVersions(const SemVer(3, 4, 5)), contains('4.0.0'));
      expect(
        legalNextVersions(const SemVer(3, 4, 5)),
        isNot(contains('4.4.5')),
      );
    });

    test('a minor bump zeroes patch', () {
      expect(legalNextVersions(const SemVer(3, 4, 5)), contains('3.5.0'));
      expect(
        legalNextVersions(const SemVer(3, 4, 5)),
        isNot(contains('3.5.5')),
      );
    });
  });

  group('isLegalTransition', () {
    test('the original accident 0.2.0 → 1.2.1 is rejected', () {
      expect(isLegalTransition(const SemVer(0, 2, 0), '1.2.1'), isFalse);
    });

    test('no change is always legal (development between releases)', () {
      expect(isLegalTransition(const SemVer(0, 2, 0), '0.2.0'), isTrue);
    });

    test('each single-axis step is legal', () {
      expect(isLegalTransition(const SemVer(0, 2, 0), '0.2.1'), isTrue);
      expect(isLegalTransition(const SemVer(0, 2, 0), '0.3.0'), isTrue);
      expect(isLegalTransition(const SemVer(0, 2, 0), '1.0.0'), isTrue);
    });

    test('skipping a patch is rejected', () {
      expect(isLegalTransition(const SemVer(0, 2, 0), '0.2.2'), isFalse);
    });

    test('a downgrade is rejected by the rule', () {
      // 1.2.1 → 0.2.2 is not a canonical step; only a deliberate entry in
      // sanctionedTransitions could ever let one through.
      expect(isLegalTransition(const SemVer(1, 2, 1), '0.2.2'), isFalse);
    });

    test('the next release after the 1.2.1 accident, 1.2.2, is legal', () {
      // The accident is left standing; the next release is the ordinary patch
      // step and passes without any exception.
      expect(isLegalTransition(const SemVer(1, 2, 1), '1.2.2'), isTrue);
    });
  });

  group('SemVer.tryParse', () {
    test('strips build metadata', () {
      final v = SemVer.tryParse('1.2.1+6');
      expect(v.toString(), '1.2.1');
    });

    test('rejects non-triples', () {
      expect(SemVer.tryParse('1.2'), isNull);
      expect(SemVer.tryParse('1.2.x'), isNull);
      expect(SemVer.tryParse(''), isNull);
    });
  });

  test('the deliberate return below 1.0 is a sanctioned exception', () {
    // The 1.2.1 accident is abandoned: the project drops back to its 0.x line
    // at 0.3.0. That downgrade is not a canonical step, so it only passes as a
    // written-down, conscious exception — visible here and in the diff.
    expect(sanctionedTransitions, contains('1.2.1->0.3.0'));
    expect(isLegalTransition(const SemVer(1, 2, 1), '0.3.0'), isFalse);
  });

  /// De basislijn mag geen proeftag zijn. Deze repo snijdt tags als
  /// `v0.4.7-rc1` om één bouwlijn op de spiegel te toetsen zonder iets uit te
  /// brengen — de tag zegt het zelf: "Geen echte release". De poort las hem als
  /// een uitgebrachte 0.4.7 en verklaarde daarmee de pubspec-versie 0.4.6 tot
  /// verboden stap terug. Elke tak stond rood op een versie die niemand had
  /// aangeraakt.
  ///
  /// De uitsluiting zit in een argumentenlijst voor `git describe`, dus alleen
  /// een echte repo met echte tags bewijst dat hij werkt.
  group('lastReleasedVersion negeert een pre-release-tag', () {
    late Directory repo;

    void git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: repo.path);
      if (r.exitCode != 0) {
        fail('git ${args.join(' ')} faalde: ${r.stderr}');
      }
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('ocideck_versietag_');
      git(['init', '--initial-branch=main']);
      git(['config', 'user.email', 'test@example.invalid']);
      git(['config', 'user.name', 'Test']);
      File('${repo.path}/leeg.txt').writeAsStringSync('x\n');
      git(['add', '.']);
      git(['commit', '-m', 'eerste']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('een release-tag is de basislijn', () {
      git(['tag', 'v0.4.6']);

      expect(lastReleasedVersion(workingDirectory: repo.path), '0.4.6');
    });

    test('een latere proeftag verdringt de release-tag niet', () {
      git(['tag', 'v0.4.6']);
      File('${repo.path}/leeg.txt').writeAsStringSync('y\n');
      git(['commit', '-am', 'tweede']);
      git(['tag', 'v0.4.7-rc1']);

      // Zonder de uitsluiting levert `git describe` hier v0.4.7-rc1 en wordt de
      // basislijn 0.4.7 — waarna pubspec 0.4.6 een "illegale stap terug" heet.
      expect(lastReleasedVersion(workingDirectory: repo.path), '0.4.6');
      expect(
        isLegalTransition(SemVer.tryParse('0.4.6')!, '0.4.6'),
        isTrue,
        reason: 'geen bump in uitvoering: de poort hoort een no-op te zijn',
      );
    });

    test('alleen proeftags: geen basislijn, dus geen oordeel', () {
      git(['tag', 'v0.5.0-rc1']);

      // Liever niets zeggen dan iets verzinnen: zonder uitgebrachte versie kan
      // de poort geen stap beoordelen, en dat is het gedocumenteerde
      // overslaan-pad (een ondiepe kloon zonder tags).
      expect(lastReleasedVersion(workingDirectory: repo.path), isNull);
    });
  });
}
