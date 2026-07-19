// Het gebundelde gezondheidslexicon (OCIWACHT §13.3, fase 13b).
//
// 62.490 aandoeningsnamen uit Orphanet, in negen talen. Deze test bewaakt drie
// dingen, en het laatste is het belangrijkste:
//
//   1. dat de namen gevonden wórden — anders is het asset dode ballast;
//   2. dat ze de scanner niet ophouden — bij 62.000 termen is dat geen
//      vanzelfsprekendheid maar het hele ontwerp van de starttoken-index;
//   3. dat de vloer blijft werken als het asset er niet is. Een privacycontrole
//      die omvalt op een ontbrekend bestand is erger dan een die minder vindt.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_bulk_lexicon.dart';
import 'package:ocideck/services/privacy/privacy_lexicon_data.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();
  final lexicon = PrivacyBulkLexicon.instance;

  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: [text]),
      ],
    ),
  );

  PrivacyFinding? healthIn2(String text, String ruleId) {
    final m = scanText(text).findings.where((f) => f.ruleId == ruleId);
    return m.isEmpty ? null : m.first;
  }

  PrivacyFinding? healthIn(String text) {
    final m = scanText(
      text,
    ).findings.where((f) => f.ruleId == 'special.health');
    return m.isEmpty ? null : m.first;
  }

  tearDown(lexicon.resetForTest);

  group('het asset zelf', () {
    test('bestaat, is geldig, en draagt zijn licentie mee', () {
      final file = File('assets/privacy/health_lexicon.json');
      expect(file.existsSync(), isTrue, reason: 'draai make refresh-lexicon');

      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      // De licentie moet in het asset staan en niet alleen in een doc: wie het
      // bestand in handen heeft, moet kunnen zien waar het vandaan komt.
      expect(map['licence'], 'CC-BY-4.0');
      expect(map['attribution'], contains('Orphanet'));
      expect(map['version'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

      final terms = (map['terms'] as Map).cast<String, dynamic>();
      expect(terms.keys, containsAll(<String>['nl', 'en', 'de', 'fr']));
      final total = terms.values.fold<int>(0, (a, b) => a + (b as List).length);
      expect(total, greaterThan(50000));
    });

    test('geen enkele term valt buiten de gemeten band', () {
      // De band is geen smaak maar een meting (zie tool/build_privacy_lexicon):
      // korter zijn acroniemen die botsen, langer zijn samenstellingen die
      // niemand voluit tikt.
      final map =
          jsonDecode(
                File('assets/privacy/health_lexicon.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final list in (map['terms'] as Map).values) {
        for (final term in (list as List).cast<String>()) {
          expect(term.length, inInclusiveRange(10, 45), reason: term);
        }
      }
    });
  });

  group('vinden', () {
    setUp(() {
      lexicon.loadForTest({
        'nl': ['Ziekte van Alexander', 'Taaislijmziekte', 'Sclerodermie'],
        'en': ['Alexander disease'],
      });
    });

    test('vindt een aandoeningsnaam midden in een zin', () {
      expect(healthIn('Bekend met taaislijmziekte sinds 2019'), isNotNull);
      expect(healthIn('Diagnose: ziekte van Alexander'), isNotNull);
    });

    test('alleen als heel woord', () {
      // Anders vindt "sclerodermie" ook een langer woord dat ermee begint.
      expect(healthIn('De sclerodermieonderzoeksgroep vergadert'), isNull);
    });

    test('de langste naam wint van een kortere die hetzelfde begint', () {
      lexicon.loadForTest({
        'nl': ['Ziekte van Alexander', 'Ziekte van Alexander type 2'],
      });
      final f = healthIn('Vastgesteld: ziekte van Alexander type 2');
      expect(f, isNotNull);
      expect(f!.end - f.start, 'ziekte van alexander type 2'.length);
    });

    test('een aandoeningsnaam is het gegeven zelf en gaat dus weg', () {
      final f = healthIn('Bekend met taaislijmziekte');
      expect(f!.role, PrivacyTermRole.value);
      expect(f.isRedactable, isTrue);
    });

    test('zonder persoon blijft het informatief', () {
      // "Onze afdeling behandelt X" is een dienstbeschrijving, geen dossier.
      final f = healthIn('Onze afdeling behandelt sclerodermie');
      expect(f!.confidence, PrivacyConfidence.possible);
    });

    test('met een persoon erbij escaleert het via de poort', () {
      final result = scanText('Mevr. De Jong is bekend met taaislijmziekte');
      final health = result.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.certain);
    });

    test('de aandoeningsnaam wint van een signaalwoord in dezelfde zin', () {
      // "diagnose" weegt 2, een aandoeningsnaam 5. De melding hoort het gegeven
      // aan te wijzen, niet het woord dat ernaar verwijst.
      final f = healthIn('De diagnose luidt sclerodermie');
      expect(f!.maskedSample, 's…e');
    });
  });

  group('zonder asset blijft de vloer staan', () {
    test('de handgeschreven trefwoorden werken gewoon door', () {
      expect(lexicon.isLoaded, isFalse);
      expect(healthIn('Bekend met diabetes'), isNotNull);
      expect(healthIn('De medicatie is aangepast'), isNotNull);
    });

    test('een taal met alleen overtuigingstermen heet niet gedekt', () {
      // Vijftien app-talen — Zweeds, Deens, Fins, Grieks, Hongaars — krijgen hun
      // termen uitsluitend uit EuroVoc en hebben géén ziektenaam. Ze "gedekt"
      // noemen zou een Zweeds dossier met een diagnose een groene balk geven
      // terwijl er voor gezondheid niets te vinden vált.
      lexicon.loadForTest({
        'sv': ['katolicism', 'protestantism'],
      }, category: 'special.religion');
      expect(privacyLexiconCoverage('sv'), PrivacyLexiconCoverage.partial);

      // Dezelfde taal mét ziektenamen is wél gedekt.
      lexicon.loadForTest({
        'sv': ['sklerodermi', 'cystinos'],
      }, category: 'special.health');
      expect(privacyLexiconCoverage('sv'), PrivacyLexiconCoverage.covered);
    });

    test('de dekkingsmeter belooft niets wat er niet is', () {
      // Pools heeft geen vloertermen. Zolang de bulk niet geladen is, hoort de
      // meter dat te zeggen — niet alvast dekking beloven.
      expect(privacyLexiconCoverage('pl'), PrivacyLexiconCoverage.none);
      lexicon.loadForTest({
        'pl': ['Chorobasomething', 'Zespol Alexandera'],
      });
      expect(privacyLexiconCoverage('pl'), PrivacyLexiconCoverage.covered);
    });
  });

  group('overtuigingen (EuroVoc)', () {
    setUp(() {
      lexicon.loadForTest({
        'nl': ['katholicisme', 'protestantisme', 'nationaal-socialisme'],
      }, category: 'special.religion');
    });

    test('een religie is het gegeven zelf, geen aanwijzing', () {
      final f = healthIn2('Betrokkene: protestantisme', 'special.religion');
      expect(f, isNotNull);
      expect(f!.role, PrivacyTermRole.value);
    });

    test('zonder persoon onderbreekt het niets', () {
      // "Onze cursus behandelt islam" is lesmateriaal, geen dossier.
      final f = healthIn2(
        'Onze cursus behandelt katholicisme',
        'special.religion',
      );
      expect(f!.confidence, PrivacyConfidence.possible);
    });

    test('met een persoon erbij escaleert het', () {
      final f = healthIn2('Dhr. Bakker: protestantisme', 'special.religion');
      expect(f!.confidence, PrivacyConfidence.certain);
    });
  });

  group('het overtuigingsasset zelf', () {
    test('draagt zijn licentie en de uitgesloten concepten mee', () {
      final map =
          jsonDecode(
                File('assets/privacy/belief_lexicon.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(map['licence'], contains('2011/833'));
      expect(map['attribution'], contains('Europese Unie'));
      // De uitsluitingen staan in het asset, niet alleen in de generator: wie
      // het bestand in handen heeft, moet kunnen zien wat er bewust uit is.
      final excluded = (map['excludedConcepts'] as Map).values.cast<String>();
      expect(excluded, contains('kerk'));
      expect(excluded, contains('theologie'));

      final terms = (map['terms'] as Map).cast<String, dynamic>();
      expect(
        terms.keys,
        containsAll(<String>[
          'special.religion',
          'special.politics',
          'special.union',
        ]),
      );
      // De reden dat deze bron erbij is: taaldekking.
      expect((terms['special.religion'] as Map).length, greaterThan(20));
    });
  });

  group('prestaties', () {
    test('62.000 termen houden de scan niet op', () async {
      await lexicon.ensureLoaded(bundle: _FileBundle());
      expect(lexicon.isLoaded, isTrue);
      expect(lexicon.termCount, greaterThan(50000));

      // Een realistische slide, ruim boven de 2 kB uit het prestatiebudget.
      final text = List.filled(
        40,
        'Het kwartaalverslag bespreekt de omzet, de bezetting en de planning '
        'voor het komende jaar in detail.',
      ).join(' ');

      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        lexicon.findIn(text.toLowerCase()).toList();
      }
      sw.stop();
      final perScan = sw.elapsedMicroseconds / 20 / 1000;
      // Het budget is 5 ms per slide voor de héle scan; deze index hoort daar
      // een fractie van te zijn. Ruim gezet omdat een testrunner geen bank is —
      // het gaat erom dat dit lineair in de tekst is en niet in het lexicon.
      expect(
        perScan,
        lessThan(5),
        reason:
            '${perScan.toStringAsFixed(2)} ms per scan van ${text.length} tekens',
      );
    });
  });
}

/// Leest het asset van schijf, zodat de test niet van een Flutter-assetbundel
/// afhangt.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }
}
