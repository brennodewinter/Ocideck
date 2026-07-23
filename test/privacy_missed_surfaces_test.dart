import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/miauw_codec.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/used_tool.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

/// Velden waar een gebruiker gegevens in kan typen en de scanner niet keek.
///
/// Wat niet gescand wordt, wordt ook niet geredigeerd: de projectie herschrijft
/// alleen de velden die een bevinding dragen. Ongescand is hier dus hetzelfde
/// als ongelakt, en dat gaat mee in de export.
///
/// Alle waarden zijn nep: `example`-domeinen en de test-BSN 728398242, die de
/// elfproef doorstaat maar bij niemand hoort.
void main() {
  const scanner = PrivacyScanner();
  const email = 'jan.jansen@voorbeeld-klant.example';

  bool findsEmail(Deck deck) =>
      scanner.scan(deck).findings.any((f) => f.ruleId == 'contact.email');

  Deck deckWith(Slide slide) => Deck(title: 'D', slides: [slide]);
  Slide plain() =>
      Slide.create(SlideType.bullets).copyWith(bullets: ['gewoon']);

  group('deckvelden', () {
    test('version en date worden gescand', () {
      expect(
        findsEmail(Deck(title: 'D', version: email, slides: [plain()])),
        isTrue,
      );
      expect(
        findsEmail(Deck(title: 'D', date: email, slides: [plain()])),
        isTrue,
      );
    });

    test('de vrije lijsten uit het informatievenster worden gescand', () {
      expect(
        findsEmail(Deck(title: 'D', standardsUsed: [email], slides: [plain()])),
        isTrue,
      );
      expect(
        findsEmail(
          Deck(
            title: 'D',
            toolsUsed: [UsedTool(name: email)],
            slides: [plain()],
          ),
        ),
        isTrue,
      );
    });

    test('MIAUW-motiveringen worden gescand', () {
      // Deze reizen base64-gecodeerd mee in de front matter: onzichtbaar voor
      // wie het bestand naleest, dus juist hier telt de scanner.
      expect(
        findsEmail(
          Deck(
            title: 'D',
            miauw: MiauwDisposition.fromTexts({'1.6': email}, const {}),
            slides: [plain()],
          ),
        ),
        isTrue,
      );
      expect(
        findsEmail(
          Deck(
            title: 'D',
            miauw: MiauwDisposition.fromTexts(const {}, {'1.6': email}),
            slides: [plain()],
          ),
        ),
        isTrue,
      );
    });
  });

  group('slidevelden', () {
    test('het scope-object van een checklist wordt gescand', () {
      expect(
        findsEmail(deckWith(plain().copyWith(checklistScope: email))),
        isTrue,
      );
    });
  });

  group('tabellen', () {
    test('een kolomkop telt mee als context voor de BSN-poort', () {
      // De gebruikelijkste manier om nummers in een deck te zetten: een kolom
      // met de naam erboven. Het contextwoord staat dan per definitie in een
      // ánder fragment dan de waarde.
      final deck = deckWith(
        Slide.create(SlideType.table).copyWith(
          tableRows: [
            ['Naam', 'BSN'],
            ['Jansen', '728398242'],
          ],
        ),
      );
      final bsn = scanner
          .scan(deck)
          .findings
          .where((f) => f.ruleId == 'nl.bsn');
      expect(bsn, hasLength(1));
      expect(
        bsn.single.confidence,
        PrivacyConfidence.certain,
        reason: 'met de kolomkop erbij is dit geen gok meer',
      );
    });

    test('zonder kolomkop blijft het een aanwijzing', () {
      final deck = deckWith(
        Slide.create(SlideType.table).copyWith(
          tableRows: [
            ['Naam', 'Nummer'],
            ['Jansen', '728398242'],
          ],
        ),
      );
      final bsn = scanner
          .scan(deck)
          .findings
          .where((f) => f.ruleId == 'nl.bsn');
      expect(bsn.single.confidence, PrivacyConfidence.possible);
    });

    test('een tabel met ongelijke rijen levert unieke celindexen', () {
      // Met `row.length` per rij botsten twee cellen op dezelfde sleutel, en
      // landde een redactie op de verkeerde cel — of buiten zijn tekst.
      final deck = deckWith(
        Slide.create(SlideType.table).copyWith(
          tableRows: [
            ['Kop A', 'Kop B', 'Kop C'],
            ['$email is lang genoeg om te botsen', 'x'],
          ],
        ),
      );
      final indexes = scanner
          .scan(deck)
          .findings
          .where((f) => f.field == 'tableRows')
          .map((f) => f.fragmentIndex)
          .toList();
      expect(indexes.toSet().length, indexes.length, reason: 'geen botsing');
    });
  });
}
