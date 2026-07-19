// Australië, India, Zuid-Afrika, de Cariben en Brazilië (OCIWACHT §15, fase 8d).
//
// Zelfde lijn als 8a t/m 8c: waar het kan een **eigenschap**, niet een
// voorbeeld. Bij deze lichting is dat extra makkelijk vol te houden, want op de
// Caribische nummers na dragen ze allemaal een echte checksum — en een checksum
// is te toetsen zonder ooit een geldig nummer op te schrijven.
//
// Eén eigenschap krijgt een eigen test, omdat hij het hele punt van de zwaarste
// van deze algoritmen is: Verhoeff vangt de verwisseling van twee buren, en Luhn
// doet dat niet. Wie Aadhaar met een Luhn zou valideren, zou `...3456...` en
// `...3546...` niet uit elkaar houden — en dat is nu juist de fout die mensen
// bij het overtypen van twaalf cijfers maken.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_checksums_world.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  Set<String> rulesIn(String text) => PrivacyScanner(regions: allPrivacyRegions)
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  /// De controlecijfers die [validate] accepteert achter [voorloop].
  List<int> passend(String voorloop, bool Function(String) validate) => [
    for (var c = 0; c <= 9; c++)
      if (validate('$voorloop$c')) c,
  ];

  group('au.tfn', () {
    test('hoogstens één controlecijfer past, en meestal precies één', () {
      // De laatste weging is 10, dus voor sommige voorlopen zou het
      // controlecijfer 10 moeten zijn en bestaat er geen geldig nummer. Dat is
      // geen fout in het algoritme maar een eigenschap ervan; de test legt
      // daarom vast dat er nooit méér dan één past.
      var metOplossing = 0;
      for (var p = 10000000; p < 10000040; p++) {
        final n = passend('$p', isValidAuTfn);
        expect(n.length, lessThanOrEqualTo(1), reason: '$p');
        if (n.length == 1) metOplossing++;
      }
      expect(metOplossing, greaterThan(20));
    });

    test('vuurt niet zonder contextwoord', () {
      final p = [
        for (var i = 10000000; i < 10000040; i++)
          if (passend('$i', isValidAuTfn).length == 1) i,
      ].first;
      final tfn = '$p${passend('$p', isValidAuTfn).single}';
      expect(rulesIn('Ordernummer $tfn'), isNot(contains('au.tfn')));
      expect(rulesIn('TFN $tfn'), contains('au.tfn'));
    });
  });

  group('au.medicare', () {
    test('het eerste cijfer ligt tussen 2 en 6', () {
      expect(passend('123456789', isValidAuMedicare), isEmpty);
      expect(passend('723456789', isValidAuMedicare), isEmpty);
    });

    test('de mod-10 discrimineert op het negende cijfer', () {
      // Het tiende cijfer is het volgnummer van de kaart en telt niet mee, dus
      // toetsen we het negende: precies één waarde hoort te passen.
      final ok = [
        for (var c = 0; c <= 9; c++)
          if (isValidAuMedicare('22345678${c}1')) c,
      ];
      expect(ok, hasLength(1));
    });
  });

  group('au.abn', () {
    test('elke enkelvoudige wijziging breekt de mod-89', () {
      final geldig = _zoekAbn();
      expect(isValidAuAbn(geldig), isTrue);
      for (var i = 0; i < 11; i++) {
        final oud = geldig[i];
        final nieuw = oud == '9' ? '8' : '9';
        final kapot = geldig.replaceRange(i, i + 1, nieuw);
        expect(isValidAuAbn(kapot), isFalse, reason: 'positie $i');
      }
    });
  });

  group('in.aadhaar — Verhoeff, en waarom dat geen Luhn is', () {
    test('precies één controlecijfer past', () {
      expect(passend('23456789012', isValidInAadhaar), hasLength(1));
      expect(passend('98765432101', isValidInAadhaar), hasLength(1));
    });

    test('begint nooit met 0 of 1', () {
      expect(passend('03456789012', isValidInAadhaar), isEmpty);
      expect(passend('13456789012', isValidInAadhaar), isEmpty);
    });

    test('vangt de verwisseling van twee buren — dit is het hele punt', () {
      final voorloop = '23456789012';
      final geldig = '$voorloop${passend(voorloop, isValidInAadhaar).single}';

      var gevonden = 0;
      for (var i = 0; i < geldig.length - 1; i++) {
        if (geldig[i] == geldig[i + 1]) continue;
        final verwisseld = geldig.replaceRange(
          i,
          i + 2,
          '${geldig[i + 1]}${geldig[i]}',
        );
        expect(
          passesVerhoeff(verwisseld),
          isFalse,
          reason: 'buren op $i verwisseld en tóch geldig',
        );
        gevonden++;
      }
      // Zonder deze ondergrens zou de test groen blijven als er niets te
      // verwisselen viel.
      expect(gevonden, greaterThan(5));
    });

    test('draagt op eigen kracht, zonder contextwoord', () {
      final voorloop = '23456789012';
      final a = '$voorloop${passend(voorloop, isValidInAadhaar).single}';
      expect(rulesIn('Referentie $a'), contains('in.aadhaar'));
    });
  });

  group('in.pan — het formaat kent het soort houder', () {
    test('alleen een natuurlijk persoon telt', () {
      // De vierde letter codeert de rechtsvorm. P is een individu; C is een
      // vennootschap en dus geen persoonsgegeven — die horen we níét te melden.
      expect(isValidInPan('ABCPE1234F'), isTrue);
      expect(isValidInPan('ABCCE1234F'), isFalse);
      expect(isValidInPan('ABCHE1234F'), isFalse);
      expect(isValidInPan('ABCTE1234F'), isFalse);
    });

    test('het formaat is strikt', () {
      expect(isValidInPan('ABCP1234F'), isFalse);
      expect(isValidInPan('ABCPE1234'), isFalse);
    });
  });

  group('za.id', () {
    test('eist een bestaande geboortedatum naast de Luhn', () {
      final goed = passend('900101500008', isValidZaId);
      expect(goed, hasLength(1));
      // Maand 13 bestaat niet, en dan helpt geen enkel controlecijfer.
      expect(passend('901301500008', isValidZaId), isEmpty);
    });
  });

  group('cw.sedula en aw.persoonsnummer', () {
    test('leunen volledig op hun contextpoort', () {
      // Geen gedocumenteerde checksum, dus zonder context mogen ze niets zeggen.
      expect(rulesIn('Ordernummer 9001011234'), isNot(contains('cw.sedula')));
      expect(rulesIn('Sedula 9001011234'), contains('cw.sedula'));
      expect(rulesIn('Persoonsnummer 12345678'), contains('aw.persoonsnummer'));
    });
  });

  group('br.cpf', () {
    test('van de honderd paren controlecijfers past er precies één', () {
      // Allebei de controlecijfers zijn afhankelijk van de negen cijfers ervóór,
      // en het tweede óók van het eerste. Je kunt ze dus niet los toetsen: de
      // eigenschap zit in het paar. Precies één van de honderd combinaties hoort
      // erdoor te komen — minder betekent dat de berekening fout is, meer dat
      // een van de twee controles niets doet.
      final ok = [
        for (var a = 0; a <= 9; a++)
          for (var b = 0; b <= 9; b++)
            if (isValidBrCpf('529011706$a$b')) '$a$b',
      ];
      expect(ok, hasLength(1));
    });

    test('elf gelijke cijfers halen beide controles en zijn tóch ongeldig', () {
      // De klassieke valkuil: 111.111.111-11 rekent perfect uit en bestaat niet.
      for (var c = 0; c <= 9; c++) {
        expect(isValidBrCpf('$c' * 11), isFalse, reason: '$c');
      }
    });
  });

  group('br.cnpj', () {
    test('veertien cijfers, en herhalingen eruit', () {
      expect(isValidBrCnpj('11111111111111'), isFalse);
      expect(isValidBrCnpj('1234567890123'), isFalse);
    });
  });
}

/// Zoekt een ABN die de mod-89 haalt, zonder er een op te schrijven.
String _zoekAbn() {
  for (var staart = 0; staart < 100000; staart++) {
    final kandidaat = '51824${staart.toString().padLeft(6, '0')}';
    if (isValidAuAbn(kandidaat)) return kandidaat;
  }
  throw StateError('geen geldige ABN gevonden — het algoritme deugt niet');
}
