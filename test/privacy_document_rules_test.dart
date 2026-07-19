// De machine-readable zone (OCIWACHT §3-B).
//
// De testvectoren hieronder zijn de officiële specimens uit ICAO 9303 — het
// paspoort van ANNA MARIA ERIKSSON uit Utopia, dat in elk deel van de norm
// opduikt. Ze staan hier niet omdat ze mooi zijn maar omdat ze extern
// controleerbaar zijn: een controlecijferformule die ik zelf verzin en zelf
// nareken, bewijst niets.
//
// De negatieven zijn belangrijker dan de positieven. Een MRZ mag geen enkele
// vals-positieve opleveren, want de melding is meteen `certain` en zegt
// "hier staat een gescand identiteitsbewijs" — dat is geen zin die je een
// gebruiker onterecht voorschotelt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_document_rules.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  // ICAO 9303 deel 4, specimen paspoort (TD3).
  const td3 =
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

  // ICAO 9303 deel 6, specimen (TD2).
  const td2 =
      'I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<\n'
      'D231458907UTO7408122F1204159<<<<<<<6';

  // ICAO 9303 deel 5, specimen identiteitskaart (TD1).
  const td1 =
      'I<UTOD231458907<<<<<<<<<<<<<<<\n'
      '7408122F1204159UTO<<<<<<<<<<<6\n'
      'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';

  group('mrzCheckDigit', () {
    test('rekent de ICAO-voorbeelden na', () {
      expect(mrzCheckDigit('D23145890'), 7);
      expect(mrzCheckDigit('L898902C3'), 6);
      expect(mrzCheckDigit('740812'), 2);
      expect(mrzCheckDigit('120415'), 9);
    });

    test('een teken dat niet in een MRZ hoort geeft niets', () {
      expect(mrzCheckDigit('abc'), isNull);
      expect(mrzCheckDigit('D2314589!'), isNull);
    });
  });

  group('findMrzZones', () {
    test('vindt alle drie de formaten', () {
      expect(findMrzZones(td3), hasLength(1));
      expect(findMrzZones(td2), hasLength(1));
      expect(findMrzZones(td1), hasLength(1));
    });

    test('de zone beslaat alle regels van de MRZ', () {
      final zone = findMrzZones(td1).single;
      expect(zone.start, 0);
      expect(zone.end, td1.length);
    });

    test('één fout controlecijfer laat de treffer vervallen', () {
      // Het samengestelde cijfer aan het eind van TD3: 0 wordt 1.
      final broken = '${td3.substring(0, td3.length - 1)}1';
      expect(findMrzZones(broken), isEmpty);
    });

    test('een onmogelijke datum laat de treffer vervallen', () {
      // Maand 13 in de geboortedatum van het TD2-specimen.
      final broken = td2.replaceFirst('7408122F', '7413122F');
      expect(findMrzZones(broken), isEmpty);
    });

    test('een regel van de juiste lengte zonder MRZ is geen MRZ', () {
      // Twee regels van precies 44 hoofdletters — vorm goed, cijfers fout.
      final blok = '${'A' * 44}\n${'B' * 44}';
      expect(findMrzZones(blok), isEmpty);
    });

    test('gewone tekst levert niets op', () {
      expect(findMrzZones('Neem je paspoort mee naar de balie'), isEmpty);
      expect(findMrzZones('KOLOM<<A\nKOLOM<<B'), isEmpty);
      expect(findMrzZones(''), isEmpty);
    });
  });

  group('doc.mrz in de scanner', () {
    const scanner = PrivacyScanner();

    PrivacyScanResult scanNotes(String text) => scanner.scan(
      Deck(
        title: 'Deck',
        slides: [Slide.create(SlideType.bullets).copyWith(notes: text)],
      ),
    );

    test('een MRZ is meteen zeker, zonder contextwoord', () {
      final result = scanNotes(td3);
      final finding = result.findings.firstWhere((f) => f.ruleId == 'doc.mrz');
      expect(finding.confidence, PrivacyConfidence.certain);
      expect(finding.family, PrivacyFamily.identifier);
    });

    test('de gevonden waarde blijft buiten de melding', () {
      final finding = scanNotes(
        td3,
      ).findings.firstWhere((f) => f.ruleId == 'doc.mrz');
      expect(finding.maskedSample.contains('ERIKSSON'), isFalse);
      expect(finding.maskedSample.contains('L898902C3'), isFalse);
    });

    test('de MRZ telt als persoon en koppelt een bijzonder gegeven', () {
      // Een gescand identiteitsbewijs náást een diagnose is precies het
      // dossierfragment waar de escalator voor bestaat.
      final result = scanner.scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(notes: td3, bullets: ['Diagnose gesteld in februari']),
          ],
        ),
      );
      final health = result.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.certain);
    });
  });
}
