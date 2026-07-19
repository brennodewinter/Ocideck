// De Amerikaanse nummers (OCIWACHT §15).
//
// ── Waarom deze test anders is opgezet dan die voor Europa ──────────────────
//
// Bij een checksumnummer kun je een geldige waarde *construeren* en weet je
// zeker dat hij niemand toebehoort zolang je hem niet publiceert. Bij het SSN
// kan dat niet: er is geen controlecijfer, dus elk getal binnen de uitgegeven
// bereiken is potentieel iemands nummer. Een testbestand met een "geldig
// voorbeeld-SSN" zet dus mogelijk een echt persoonsnummer in de repo — precies
// het gedrag dat deze scanner hoort af te keuren.
//
// Daarom toetst deze test waar mogelijk een **eigenschap** in plaats van een
// voorbeeld: hoeveel van de mogelijke gebiedsnummers het algoritme accepteert,
// niet of één specifiek nummer erdoorheen komt. Waar toch een string nodig is
// (de scanner werkt nu eenmaal op tekst) staat er een nummer uit een bereik dat
// bestaat, en dat is een erkende beperking en geen slordigheid: er ís geen
// bewijsbaar onuitgegeven SSN.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_checksums_world.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  Set<String> rulesIn(String text, {Set<String>? regions}) =>
      PrivacyScanner(regions: regions ?? {...defaultPrivacyRegions, 'us'})
          .scan(
            Deck(
              title: 'Deck',
              slides: [
                Slide.create(SlideType.bullets).copyWith(bullets: [text]),
              ],
            ),
          )
          .firedRules;

  group('us.ssn — bereikregels in plaats van een checksum', () {
    test('accepteert precies de uitgegeven gebiedsnummers', () {
      // Gebied 001-899, behalve 666. Dat zijn er 898. Deze telling is de
      // eigenlijke assertie: hij faalt zowel wanneer een bereik te ruim wordt
      // (900 erbij) als wanneer het te krap wordt (666 blijft eruit).
      final geaccepteerd = [
        for (var area = 0; area <= 999; area++)
          if (isValidUsSsn('${area.toString().padLeft(3, '0')}451234')) area,
      ];
      expect(geaccepteerd.length, 898);
      expect(geaccepteerd, isNot(contains(0)));
      expect(geaccepteerd, isNot(contains(666)));
      expect(geaccepteerd, isNot(contains(900)));
      expect(geaccepteerd.last, 899);
    });

    test('groep 00 en volgnummer 0000 zijn nooit uitgegeven', () {
      expect(isValidUsSsn('123001234'), isFalse);
      expect(isValidUsSsn('123450000'), isFalse);
    });

    test('de bekende voorbeeldnummers worden overgeslagen', () {
      // 078-05-1120 stond in 1938 op een proefkaart in portefeuilles van
      // Woolworth; duizenden mensen gaven het daarna als het hunne op. Rood
      // kleuren op een slide die juist dát verhaal vertelt, maakt de scanner
      // ongeloofwaardig.
      expect(isValidUsSsn('078-05-1120'), isFalse);
      expect(isValidUsSsn('123-45-6789'), isFalse);
      expect(isValidUsSsn('219-09-9999'), isFalse);
    });

    test('zonder contextwoord vuurt de regel niet', () {
      // Negen cijfers zonder meer is een ordernummer, een artikelcode, een
      // klantnummer. De bereikcontrole schrapt maar een paar procent, dus de
      // contextpoort is hier geen verfijning maar de dragende constructie.
      expect(rulesIn('Ordernummer 665-99-9418'), isNot(contains('us.ssn')));
      expect(rulesIn('SSN: 665-99-9418'), contains('us.ssn'));
    });

    test('staat uit zolang het VS-pakket niet gekozen is', () {
      // Fase 8a levert de regels; het verplaatsen van `us` naar de
      // standaardregio's hoort bij 8c, wanneer de hele Amerikaanse set er is.
      expect(
        rulesIn('SSN: 665-99-9418', regions: defaultPrivacyRegions),
        isNot(contains('us.ssn')),
      );
    });
  });

  group('us.itin', () {
    test('eist een 9 vooraan en een toegewezen groep', () {
      expect(isValidUsItin('912-70-1234'), isTrue);
      expect(isValidUsItin('812-70-1234'), isFalse); // begint niet met 9
      expect(isValidUsItin('912-69-1234'), isFalse); // groep buiten bereik
      expect(isValidUsItin('912-93-1234'), isFalse); // gat tussen 92 en 94
    });

    test('vuurt met context', () {
      expect(rulesIn('ITIN 912-70-1234'), contains('us.itin'));
      expect(rulesIn('Referentie 912-70-1234'), isNot(contains('us.itin')));
    });
  });

  group('us.ein', () {
    test('toetst het uitgiftecampus-prefix', () {
      expect(isValidUsEin('12-3456789'), isTrue);
      expect(isValidUsEin('07-3456789'), isFalse); // bestaat niet
      expect(isValidUsEin('19-3456789'), isFalse);
      expect(isValidUsEin('96-3456789'), isFalse);
    });

    test('het streepje scheidt hem van een SSN', () {
      // Beide zijn negen cijfers; alleen de plaats van het koppelteken
      // onderscheidt ze. Zonder die eis zouden de twee regels elkaars treffers
      // overnemen en zou een EIN als persoonsnummer gemeld worden.
      expect(rulesIn('EIN 12-3456789'), contains('us.ein'));
      expect(rulesIn('EIN 123456789'), isNot(contains('us.ein')));
    });
  });

  group('us.ssn_last4 — het gemaskeerde idioom', () {
    test('herkent de gangbare maskeringen', () {
      expect(rulesIn('SSN XXX-XX-4412'), contains('us.ssn_last4'));
      expect(rulesIn('social security ***-**-4412'), contains('us.ssn_last4'));
    });

    test('laat gewone tekst met vier cijfers met rust', () {
      expect(rulesIn('Bestelling 4412'), isNot(contains('us.ssn_last4')));
      expect(rulesIn('XXX-XX-44120'), isNot(contains('us.ssn_last4')));
    });
  });

  group('ABA routing', () {
    test('de mod-10 met 3-7-1 discrimineert', () {
      // Voor een gegeven voorloop hoort precies één controlecijfer te passen.
      // Dat is te meten zonder een gepubliceerd voorbeeldnummer, en het toetst
      // het algoritme in plaats van mijn geheugen ervan.
      final passend = [
        for (var laatste = 0; laatste <= 9; laatste++)
          if (isValidAbaRouting('02100002$laatste')) laatste,
      ];
      expect(passend, hasLength(1));
    });

    test('wijst onmogelijke districten af', () {
      expect(isValidAbaRouting('000000000'), isFalse);
      expect(isValidAbaRouting('400000004'), isFalse); // 40 bestaat niet
    });
  });
}
