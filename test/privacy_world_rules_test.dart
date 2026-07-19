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

    test('draait mee bij een standaardinstallatie', () {
      // §15.6: `us` staat sinds de hele Amerikaanse set af in
      // defaultPrivacyRegions. Zonder dit zou al het werk aan 8a en 8c
      // onzichtbaar blijven voor wie de chip niet kent — en dat is precies de
      // gebruiker die de controle het hardst nodig heeft.
      expect(
        rulesIn('SSN: 665-99-9418', regions: defaultPrivacyRegions),
        contains('us.ssn'),
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

    test('vuurt met context en zwijgt zonder', () {
      // Negen cijfers halen de mod-10 één op de tien keer, dus ook hier draagt
      // de contextpoort mee.
      expect(rulesIn('Routing number 021000021'), contains('fin.us_routing'));
      expect(
        rulesIn('Artikelcode 021000021'),
        isNot(contains('fin.us_routing')),
      );
    });

    test('hangt niet aan het VS-pakket', () {
      // Anders dan us.ssn: financiële data hoort niet stil te blijven omdat
      // iemand een landchip uit had staan.
      expect(
        rulesIn('Routing number 021000021', regions: defaultPrivacyRegions),
        contains('fin.us_routing'),
      );
    });
  });

  // ── De zorgnummers ─────────────────────────────────────────────────────────
  //
  // Dezelfde terughoudendheid als hierboven, om een andere reden. Een NPI staat
  // in een openbaar register: een "geldig voorbeeld" dat ik hier construeer,
  // is met redelijke kans het nummer van een echte zorgverlener. Dus ook hier
  // eigenschappen in plaats van voorbeelden, behalve waar CMS zélf een
  // voorbeeldnummer publiceert.

  group('us.npi', () {
    test('precies één controlecijfer past bij een gegeven voorloop', () {
      // Toetst het algoritme (Luhn over 80840 + negen cijfers) in plaats van
      // mijn geheugen van een voorbeeldnummer.
      final passend = [
        for (var laatste = 0; laatste <= 9; laatste++)
          if (isValidUsNpi('123456789$laatste')) laatste,
      ];
      expect(passend, hasLength(1));
    });

    test('alleen 1 en 2 zijn uitgegeven voorlopen', () {
      // Zoek voor elke beginpositie het passende controlecijfer; alleen 1 en 2
      // horen überhaupt een geldige uitkomst te kunnen geven.
      final geaccepteerd = [
        for (var eerste = 0; eerste <= 9; eerste++)
          if ([
            for (var laatste = 0; laatste <= 9; laatste++)
              if (isValidUsNpi('${eerste}23456789$laatste')) laatste,
          ].isNotEmpty)
            eerste,
      ];
      expect(geaccepteerd, [1, 2]);
    });

    test('vuurt met context en zwijgt zonder', () {
      // Luhn over tien cijfers laat één op de tien door, dus de poort draagt
      // hier het bewijs — niet de checksum.
      expect(rulesIn('NPI 1234567893'), contains('us.npi'));
      expect(rulesIn('Bestelnummer 1234567893'), isNot(contains('us.npi')));
    });
  });

  group('us.medicare_mbi', () {
    test('het voorbeeldnummer van CMS is geldig', () {
      // Uit de CMS-documentatie, met en zonder koppeltekens.
      expect(isValidUsMbi('1EG4-TE5-MK73'), isTrue);
      expect(isValidUsMbi('1EG4TE5MK73'), isTrue);
    });

    test('de zes verwarrende letters zijn uitgesloten', () {
      // S/5, L/1, O/0, I/1, B/8, Z/2 — eruit gelaten omdat ze bij overtypen op
      // een cijfer lijken. Twintig van de zesentwintig blijven over.
      final toegestaan = [
        for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
          if (isValidUsMbi('1${c}G4TE5MK73')) c,
      ];
      expect(toegestaan, hasLength(20));
      for (final uit in ['S', 'L', 'O', 'I', 'B', 'Z']) {
        expect(toegestaan, isNot(contains(uit)), reason: '\$uit hoort eruit');
      }
    });

    test('positie 1 is nooit nul', () {
      expect(isValidUsMbi('0EG4TE5MK73'), isFalse);
    });

    test('vuurt met context en zwijgt zonder', () {
      // Er is geen checksum; de vorm alleen is niet genoeg, want een
      // artikelnummer kan dezelfde afwisseling volgen.
      expect(rulesIn('MBI 1EG4-TE5-MK73'), contains('us.medicare_mbi'));
      expect(
        rulesIn('Artikel 1EG4-TE5-MK73'),
        isNot(contains('us.medicare_mbi')),
      );
    });
  });

  group('us.dea', () {
    test('precies één controlecijfer past bij een gegeven voorloop', () {
      final passend = [
        for (var laatste = 0; laatste <= 9; laatste++)
          if (isValidUsDea('AB123456$laatste')) laatste,
      ];
      expect(passend, hasLength(1));
    });

    test('wijst een onbestaand registrantentype af', () {
      // De eerste letter is het type; V en W zijn niet uitgegeven.
      expect(isValidUsDea('AB1234563'), isTrue);
      expect(isValidUsDea('VB1234563'), isFalse);
    });

    test('vuurt met context en zwijgt zonder', () {
      expect(rulesIn('DEA AB1234563'), contains('us.dea'));
      expect(rulesIn('Code AB1234563'), isNot(contains('us.dea')));
    });
  });
}
