// Het lexicon als data (OCIWACHT §13.2, fase 12).
//
// Tot fase 12 werd de matchmodus afgeleid uit de termlengte, met vier tekens als
// grens. Dat werkte verrassend ver, maar de uitzonderingen zijn niet zeldzaam en
// ze gaan beide kanten op: `arrest` is lang genoeg voor de voorvoegselregel en
// moet tóch een heel woord zijn, en `ziekteverzuim` moet juist middenin een
// samenstelling gevonden worden. Deze test bewaakt dat die twee nu allebei
// kloppen — en dat het gewicht bepaalt wélke term de melding draagt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/privacy_lexicon.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_lexicon_data.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_special_rules.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: [text]),
      ],
    ),
  );

  Set<String> rulesIn(String text) => scanText(text).firedRules;

  PrivacyFinding? findingFor(String text, String ruleId) {
    final matches = scanText(text).findings.where((f) => f.ruleId == ruleId);
    return matches.isEmpty ? null : matches.first;
  }

  group('de matchmodus komt uit het lexicon', () {
    test('word matcht alleen een heel woord', () {
      expect(
        findPrivacyTermIn('de vogels vliegen', 'vog', PrivacyTermMatch.word),
        -1,
      );
      expect(
        findPrivacyTermIn('een vog aanvragen', 'vog', PrivacyTermMatch.word),
        4,
      );
    });

    test('prefix laat het achtervoegsel vrij', () {
      expect(
        findPrivacyTermIn(
          'wordt verdacht van',
          'verdacht',
          PrivacyTermMatch.prefix,
        ),
        6,
      );
      expect(
        findPrivacyTermIn(
          'alle verdachten gehoord',
          'verdacht',
          PrivacyTermMatch.prefix,
        ),
        5,
      );
      // Maar niet middenin: `raad` mag de voorraad niet vinden.
      expect(
        findPrivacyTermIn('de voorraad is op', 'raad', PrivacyTermMatch.prefix),
        -1,
      );
    });

    test('compound matcht ook middenin een samenstelling', () {
      expect(
        findPrivacyTermIn(
          'de ziekteverzuimcijfers stegen',
          'ziekteverzuim',
          PrivacyTermMatch.compound,
        ),
        3,
      );
      expect(
        findPrivacyTermIn(
          'het langdurigziekteverzuim',
          'ziekteverzuim',
          PrivacyTermMatch.compound,
        ),
        13,
      );
    });

    test('een korte term valt terug van compound naar prefix', () {
      // Anders zit `arts` in `kaarts` en verdampt de winst van decompounding.
      const entry = PrivacyLexiconEntry(
        term: 'arts',
        category: 'special.health',
        lang: 'nl',
        match: PrivacyTermMatch.compound,
      );
      expect(entry.effectiveMatch, PrivacyTermMatch.prefix);
    });
  });

  group('het gedrag dat de oude lengteregel niet kon', () {
    test('arrest is een heel woord, ondanks zijn lengte', () {
      // Zes letters, dus onder de oude regel een voorvoegsel. Maar het is ook
      // een uitspraak van de Hoge Raad, en dat woord staat in elk juridisch deck.
      expect(rulesIn('Het arrestatiebevel is getekend'), isEmpty);
    });

    test('ziekteverzuim wordt in een samenstelling gevonden', () {
      expect(
        rulesIn('De ziekteverzuimcijfers van deze afdeling'),
        contains('special.health'),
      );
    });
  });

  group('het gewicht kiest de melding', () {
    test('de meest specifieke term draagt de melding, niet de eerste', () {
      // Beide termen staan in de zin. `diagnose` staat vooraan in het lexicon en
      // is laag gewogen (het valt in elke projectvergadering); `ziekteverzuim`
      // heeft geen tweede betekenis en wint dus.
      final finding = findingFor(
        'De diagnose leidde tot ziekteverzuim',
        'special.health',
      );
      expect(finding, isNotNull);
      expect(finding!.maskedSample, 'z…m');
    });

    test('tien synoniemen in één zin geven nog steeds één melding', () {
      final health = scanText(
        'diagnose, medicatie, zwangerschap, verslaving, depressie',
      ).findings.where((f) => f.ruleId == 'special.health');
      expect(health, hasLength(1));
    });
  });

  group('de rol komt uit het lexicon', () {
    test('een aanwijzing blijft een aanwijzing', () {
      final finding = findingFor('De diagnose is gesteld', 'special.health');
      expect(finding!.role, PrivacyTermRole.indicator);
    });

    test('een aandoening is het gegeven zelf', () {
      // "diabetes" wijst niet naar een gezondheidsgegeven — het ís er een. Dat
      // verschil bepaalt of redactie werkelijk iets weghaalt.
      final finding = findingFor('Bekend met diabetes', 'special.health');
      expect(finding!.role, PrivacyTermRole.value);
      expect(finding.isRedactable, isTrue);
    });
  });

  group('special.icd10 en special.atc', () {
    test('vuren alleen met een contextwoord', () {
      // `A12` is ook een tabelverwijzing, een zaalnummer en een vitamine.
      expect(rulesIn('Zie tabel A12 op pagina 4'), isEmpty);
      expect(
        rulesIn('Hoofddiagnose F32.1 vastgesteld'),
        contains('special.icd10'),
      );
      expect(rulesIn('Artikelcode J01CA04 besteld'), isEmpty);
      expect(
        rulesIn('Geneesmiddel J01CA04 voorgeschreven'),
        contains('special.atc'),
      );
    });

    test('een diagnosecode is het gegeven zelf en gaat dus weg', () {
      final finding = findingFor('Hoofddiagnose F32.1', 'special.icd10');
      expect(finding!.isRedactable, isTrue);
    });
  });

  group('taaldekking', () {
    test('het lexicon weet in welke talen het iets te zoeken heeft', () {
      // De basis voor de dekkingsmeter van fase 13. Nederlands en Engels horen
      // er zeker in te zitten; het punt is dat de verzameling eindig is en
      // opvraagbaar, niet dat hij compleet is.
      expect(privacyLexiconLanguages, contains('nl'));
      expect(privacyLexiconLanguages, contains('en'));
      // De interface draait in 30 talen; het lexicon dekt er een handvol.
      expect(privacyLexiconLanguages.length, lessThan(10));
    });

    test('elke entry draagt een taal en een gewicht binnen bereik', () {
      for (final entry in bundledPrivacyLexicon) {
        expect(entry.lang, isNotEmpty, reason: entry.term);
        expect(entry.term, entry.term.toLowerCase(), reason: entry.term);
        expect(entry.weight, inInclusiveRange(1, 5), reason: entry.term);
      }
    });
  });
}
