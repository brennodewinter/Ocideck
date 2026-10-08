// Slaat Windows over om dezelfde reden als homebrew_cask_test.dart: de test
// roept `bash scripts/verify_homebrew_cask.sh` aan (curl/sed/date), en de cask
// is macOS-only — op Windows draait dat script niet in productie.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/release_manifest_test_support.dart';

/// De terugleescontrole op de Homebrew-tap
/// (`scripts/verify_homebrew_cask.sh`).
///
/// De releaseketen duwde de cask vroeger zelf naar de tap, met een persoonlijk
/// toegangstoken in `HOMEBREW_TAP_TOKEN`. Dat token weigerde de forge bij
/// v0.4.8 (HTTP 401) en de tap stond drie releases achter voordat iemand het
/// merkte. Sindsdien is het omgedraaid: de tap houdt zichzelf bij met een eigen
/// werkstroom en het per-run Actions-token van Forgejo, en deze repository
/// levert alleen nog de bouwstenen. Er is dus geen secret meer dat kan
/// verlopen — maar wél een koppeling over repo-grenzen heen, en die is stil:
/// hernoem je het script, de sjabloon of de publieke sleutel, dan breekt de
/// tap zonder dat hier iets rood wordt. Vandaar dat die drie paden hieronder
/// gepind staan.
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

    test('een achtergebleven cask is rood en wijst naar de tapworkflow', () {
      final r = run(['v0.4.7'], tap: writeCask('tap', '0.4.6'));
      expect(r.exitCode, isNot(0));
      // De melding moet de dader noemen, niet alleen dat er iets niet klopt.
      // De tap werkt zichzelf bij, dus de herstelroute is diens
      // update-workflow — niet het afgeschafte duwtoken dat hier vroeger
      // stond en de beheerder bij v0.6.14 het verkeerde bos in stuurde.
      expect(r.stderr, contains('homebrew-ocideck'));
      expect(r.stderr, contains('actions'));
      expect(r.stderr, isNot(contains('HOMEBREW_TAP_TOKEN')));
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
    test('de releaseketen duwt de cask niet meer naar de tap', () {
      final doc =
          loadYaml(File('.forgejo/workflows/release.yml').readAsStringSync())
              as YamlMap;

      expect(
        (doc['jobs'] as YamlMap).keys,
        isNot(contains('homebrew-cask')),
        reason:
            'de cask-job is terug in de releaseketen; die route hing aan '
            'HOMEBREW_TAP_TOKEN en viel stil om. De tap werkt zichzelf bij.',
      );
      expect(
        File('.forgejo/workflows/release.yml').readAsStringSync(),
        isNot(contains('HOMEBREW_TAP_TOKEN')),
        reason:
            'de releaseketen leunt weer op een tap-token; dat is precies het '
            'onderdeel dat we kwijt wilden',
      );
    });

    test('de bouwstenen liggen op de paden die de tap ophaalt', () {
      // De werkstroom in LibreKAT/homebrew-ocideck haalt deze drie bestanden
      // per run op via `raw/<pad>?ref=<tag>`: het script, de sjabloon én de
      // publieke sleutel waartegen het script SHA256SUMS.minisig verifieert.
      // Die koppeling staat in een andere repository en kan hier dus niet
      // meelopen in een refactor: verplaats je ze, dan blijft de tap stil op
      // de oude release staan — bij v0.6.14 bleek dat met minisign.pub.
      for (final pad in const [
        'scripts/update_homebrew_cask.sh',
        'homebrew/ocideck.rb.tmpl',
        'minisign.pub',
      ]) {
        expect(
          File(pad).existsSync(),
          isTrue,
          reason:
              '$pad ontbreekt; de werkstroom van de tap haalt precies dit pad '
              'op en breekt zonder melding in deze repository',
        );
      }
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

  group('het taggebonden bouwcontract', () {
    // De tapworkflow draait de generator in een checkout van díe tag: het
    // script bepaalt zijn repo-root zelf (dirname van het script) en zoekt
    // template en sleutel daaronder. Deze tests bootsen die layout na door de
    // drie bouwstenen naar een schone tag-root te kopiëren, zodat bewezen is
    // dat ze daar samen op de verwachte paden staan — precies wat bij v0.6.14
    // stuk ging, toen de sleutel nog niet mee opgehaald werd.
    Directory writeTagLayout({bool metSleutel = true}) {
      final tagRoot = Directory('${temp.path}/tag${temp.listSync().length}')
        ..createSync(recursive: true);
      Directory('${tagRoot.path}/scripts').createSync();
      Directory('${tagRoot.path}/homebrew').createSync();
      for (final pad in [
        'scripts/update_homebrew_cask.sh',
        'homebrew/ocideck.rb.tmpl',
        if (metSleutel) 'minisign.pub',
      ]) {
        File('$repoRoot/$pad').copySync('${tagRoot.path}/$pad');
      }
      return tagRoot;
    }

    File writeSignedSums(String version) {
      const macSha =
          '9e199155b109b195bf0a3c0a8303f181debf23c8cb06b7585a393dce461176e6';
      final sums = File('${temp.path}/SHA256SUMS-$version')
        ..writeAsStringSync(
          'aaaa  ./ocideck-$version.cdx.json\n'
          '$macSha  ./ocideck-macos-$version.zip\n',
        );
      signTestManifest(sums);
      return sums;
    }

    ProcessResult runGenerator(Directory tagRoot, File sums, String out) =>
        Process.runSync(
          'bash',
          ['scripts/update_homebrew_cask.sh', 'v9.9.9', out],
          workingDirectory: tagRoot.path,
          environment: {
            'SHA256SUMS_FILE': sums.path,
            'PATH': '${temp.path}:${Platform.environment['PATH']}',
          },
        );

    test('script, sjabloon en sleutel op hun tagpaden leveren een cask', () {
      writeFakeMinisign(temp);
      final tagRoot = writeTagLayout();
      final out = '${temp.path}/ocideck.rb';

      final r = runGenerator(tagRoot, writeSignedSums('9.9.9'), out);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        File(out).readAsStringSync(),
        contains(
          'sha256 '
          '"9e199155b109b195bf0a3c0a8303f181debf23c8cb06b7585a393dce461176e6"',
        ),
      );
    });

    test('een ontbrekende sleutel blijft fail-closed', () {
      writeFakeMinisign(temp);
      final tagRoot = writeTagLayout(metSleutel: false);
      final out = '${temp.path}/ocideck.rb';

      final r = runGenerator(tagRoot, writeSignedSums('9.9.9'), out);

      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('minisign public key'));
      expect(File(out).existsSync(), isFalse);
    });
  });
}
