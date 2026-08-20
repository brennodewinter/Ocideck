// Slaat Windows over om dezelfde reden als homebrew_cask_test.dart: de test
// roept `bash scripts/verify_homebrew_cask.sh` aan (curl/sed/date), en de cask
// is macOS-only — op Windows draait dat script niet in productie.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// De terugleescontrole op de Homebrew-tap
/// (`scripts/verify_homebrew_cask.sh`).
///
/// De cask-stap in `.forgejo/workflows/release.yml` slikt een mislukte clone
/// bewust in (`exit 0`), zodat een onbereikbare tap een afgeronde release niet
/// rood maakt. Daardoor las een groene job óók als "tap bijgewerkt" terwijl er
/// niets gepusht was: een ingetrokken `HOMEBREW_TAP_TOKEN` bleef onzichtbaar
/// tot iemand via `brew` een oude versie installeerde.
///
/// Eén hop verderop zit dezelfde faalklasse: de GitHub-spiegel van de tap. Die
/// is een reservekopie, maar Homebrews `brew tap`-shorthand lost er wél naar
/// op, dus een stilgevallen spiegel serveert oude casks terwijl de forge bij
/// is. Spiegelen is asynchroon, dus dat mag pas rood worden ná een respijt —
/// vandaar `--mirror` in een dagelijkse werkstroom in plaats van in de release.
///
/// De tests pinnen beide oordelen én beide stukken bedrading: een script dat
/// niemand aanroept bewaakt niets.
void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('brew_verify');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File writeCask(String naam, String version) => File('${temp.path}/$naam.rb')
    ..writeAsStringSync(
      'cask "ocideck" do\n'
      '  version "$version"\n'
      '  sha256 "abc"\n'
      'end\n',
    );

  // Zonder fractie van seconden: BSD `date -j -f` (macOS) kent het formaat met
  // microseconden dat Dart standaard schrijft niet, GNU `date -d` wel. Een
  // testfixture mag dat verschil niet importeren.
  String iso(DateTime t) => '${t.toUtc().toIso8601String().split('.').first}Z';

  // CASK_FILE/MIRROR_CASK_FILE en RELEASE_PUBLISHED_AT houden de test offline:
  // zonder die haken zou het script de tap, de spiegel en de release-API over
  // het netwerk bevragen en zou de uitkomst van de dag afhangen.
  ProcessResult run(
    List<String> args, {
    File? tap,
    File? mirror,
    DateTime? published,
  }) => Process.runSync(
    'bash',
    ['scripts/verify_homebrew_cask.sh', ...args],
    workingDirectory: repoRoot,
    environment: {
      if (tap != null) 'CASK_FILE': tap.path,
      if (mirror != null) 'MIRROR_CASK_FILE': mirror.path,
      if (published != null) 'RELEASE_PUBLISHED_AT': iso(published),
    },
  );

  group('de tap zelf', () {
    test('een cask op de releaseversie is groen', () {
      final r = run(['v0.4.6'], tap: writeCask('tap', '0.4.6'));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('0.4.6'));
    });

    test('een achtergebleven cask is rood', () {
      final r = run(['v0.4.7'], tap: writeCask('tap', '0.4.6'));
      expect(r.exitCode, isNot(0));
      // De melding moet de dader noemen, niet alleen dat er iets niet klopt:
      // wie dit in een release-log tegenkomt moet weten waar hij moet kijken.
      expect(r.stderr, contains('HOMEBREW_TAP_TOKEN'));
    });

    test('een cask zonder versieregel is rood', () {
      final leeg = File('${temp.path}/leeg.rb')
        ..writeAsStringSync('cask do\nend\n');
      expect(run(['v0.4.6'], tap: leeg).exitCode, isNot(0));
    });

    test('een ontbrekend cask-bestand is rood', () {
      final weg = File('${temp.path}/bestaat-niet.rb');
      expect(run(['v0.4.6'], tap: weg).exitCode, isNot(0));
    });

    test('een prerelease-tag wordt niet getoetst', () {
      // De generator publiceert prereleases niet naar de tap, dus daar blijven
      // staan op de vorige stabiele versie is juist goed gedrag.
      final r = run(['v0.5.0-rc1'], tap: writeCask('tap', '0.4.6'));
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });
  });

  group('de spiegel', () {
    test('een bijgewerkte spiegel is groen', () {
      final r = run(
        ['--mirror', 'v0.4.6'],
        tap: writeCask('tap', '0.4.6'),
        mirror: writeCask('spiegel', '0.4.6'),
        published: DateTime.utc(2026, 1, 1),
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('Mirror'));
    });

    test('een achtergebleven spiegel is rood zodra het respijt om is', () {
      final r = run(
        ['--mirror', 'v0.4.6'],
        tap: writeCask('tap', '0.4.6'),
        mirror: writeCask('spiegel', '0.4.5'),
        published: DateTime.utc(2026, 1, 1),
      );
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('stale'));
      // De tap is in dit geval juist wél goed; de melding moet niet naar het
      // tap-token wijzen maar naar het spiegelen.
      expect(r.stderr, contains('push-mirror'));
    });

    test('binnen het respijt is een achterlopende spiegel geen fout', () {
      // Vlak na een release is achterlopen normaal: het spiegelen is
      // asynchroon. Zou dit rood zijn, dan stond de controle elke release een
      // dag lang te loeien en keek er niemand meer naar.
      final r = run(
        ['--mirror', 'v0.4.6'],
        tap: writeCask('tap', '0.4.6'),
        mirror: writeCask('spiegel', '0.4.5'),
        published: DateTime.now(),
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('grace'));
    });

    test('zonder --mirror blijft de spiegel buiten beschouwing', () {
      // Dit is waarom de releaseketen de spiegel niet toetst: een verse
      // release met een nog niet gespiegelde tap mag niet rood zijn.
      final r = run(
        ['v0.4.6'],
        tap: writeCask('tap', '0.4.6'),
        mirror: writeCask('spiegel', '0.1.0'),
        published: DateTime.utc(2026, 1, 1),
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, isNot(contains('Mirror')));
    });
  });

  group('de bedrading', () {
    test('de releaseketen draait de controle na het pushen', () {
      final file = File('.forgejo/workflows/release.yml');
      expect(file.existsSync(), isTrue, reason: 'release.yml niet gevonden');

      final doc = loadYaml(file.readAsStringSync()) as YamlMap;
      final job = (doc['jobs'] as YamlMap)['homebrew-cask'] as YamlMap;
      final steps = (job['steps'] as YamlList).toList();

      final duwt = steps.indexWhere(
        (s) =>
            ((s as YamlMap)['run'] as String?)?.contains('git push') ?? false,
      );
      final toetst = steps.indexWhere(
        (s) =>
            ((s as YamlMap)['run'] as String?)?.contains(
              'verify_homebrew_cask.sh',
            ) ??
            false,
      );

      expect(duwt, isNot(-1), reason: 'geen push-stap in de cask-job');
      expect(
        toetst,
        isNot(-1),
        reason:
            'de cask-job draait verify_homebrew_cask.sh niet; een groene job '
            'zegt dan opnieuw niets over wat er in de tap staat',
      );
      expect(
        toetst,
        greaterThan(duwt),
        reason:
            'de controle moet ná het pushen lezen, anders toetst hij de '
            'vorige release',
      );
    });

    test('de spiegelcontrole draait periodiek, niet in de release', () {
      final file = File('.forgejo/workflows/tap-mirror-check.yml');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'tap-mirror-check.yml niet gevonden; zonder periodieke controle '
            'ziet niemand een stilgevallen spiegel',
      );

      final doc = loadYaml(file.readAsStringSync()) as YamlMap;
      // `on:` leest YAML als de boolean true (de YAML 1.1-erfenis), dus vraag
      // beide vormen op in plaats van te gokken welke deze parser teruggeeft.
      final triggers = (doc[true] ?? doc['on']) as YamlMap;
      expect(
        triggers.keys,
        contains('schedule'),
        reason: 'zonder schedule-trigger draait de spiegelcontrole nooit',
      );

      final runs =
          ((doc['jobs'] as YamlMap).values.first as YamlMap)['steps']
              as YamlList;
      expect(
        runs.any(
          (s) =>
              ((s as YamlMap)['run'] as String?)?.contains(
                'verify_homebrew_cask.sh --mirror',
              ) ??
              false,
        ),
        isTrue,
        reason: 'de periodieke job draait het script niet met --mirror',
      );

      // De releaseketen mag de spiegel juist níet toetsen: spiegelen is
      // asynchroon, dus daar zou --mirror een verse release rood maken.
      final release = File('.forgejo/workflows/release.yml').readAsStringSync();
      expect(
        release,
        isNot(contains('verify_homebrew_cask.sh --mirror')),
        reason:
            'de releaseketen toetst de spiegel; die loopt vlak na een release '
            'normaal achter en maakt de release dan onterecht rood',
      );
    });
  });
}
