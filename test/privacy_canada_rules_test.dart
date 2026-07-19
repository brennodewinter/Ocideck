// De Canadese nummers (OCIWACHT §15, fase 8b).
//
// Dezelfde opzet als bij de Amerikaanse: waar mogelijk een **eigenschap** in
// plaats van een voorbeeld. Bij een checksumnummer is dat niet alleen netter
// maar ook eerlijker — het toetst het algoritme, niet mijn geheugen ervan.
//
// Voor `ca.ohip` doet die keuze extra werk. Of het tiende cijfer werkelijk een
// Luhn-controle is, heb ik niet tegen een gezaghebbende bron kunnen leggen; de
// bewering circuleert wel. De test hieronder stelt daarom vast dát de
// implementatie discrimineert (precies één controlecijfer past), en niet dat
// Luhn het juiste algoritme ís. Zolang dat open staat draagt de regel een
// contextpoort en blijft hij op `likely`, zodat een verkeerde keuze hooguit
// treffers mist in plaats van valse zekerheid produceert.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_checksums_world.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  Set<String> rulesIn(String text, {Set<String>? regions}) =>
      PrivacyScanner(regions: regions ?? {...defaultPrivacyRegions, 'ca'})
          .scan(
            Deck(
              title: 'Deck',
              slides: [
                Slide.create(SlideType.bullets).copyWith(bullets: [text]),
              ],
            ),
          )
          .firedRules;

  /// De controlecijfers die [validate] accepteert voor een gegeven [voorloop].
  List<int> passendeCijfers(String voorloop, bool Function(String) validate) =>
      [
        for (var c = 0; c <= 9; c++)
          if (validate('$voorloop$c')) c,
      ];

  group('ca.sin', () {
    test('de Luhn discrimineert: precies één controlecijfer past', () {
      expect(passendeCijfers('12345678', isValidCaSin), hasLength(1));
      expect(passendeCijfers('19283746', isValidCaSin), hasLength(1));
    });

    test('0 en 8 zijn nooit als eerste cijfer uitgegeven', () {
      // Deze eis doet echt werk naast de Luhn: hij haalt een vijfde van de
      // ruimte weg die de checksum alleen niet raakt.
      expect(passendeCijfers('01234567', isValidCaSin), isEmpty);
      expect(passendeCijfers('81234567', isValidCaSin), isEmpty);
    });

    test('de bekende testwaarde wordt overgeslagen', () {
      // 046 454 286 staat in vrijwel elke SIN-validator als voorbeeld; hij haalt
      // de Luhn en zou zonder deze uitsluiting elke handleiding rood kleuren.
      expect(isValidCaSin('046454286'), isFalse);
    });

    test('zonder contextwoord vuurt de regel niet', () {
      final geldig =
          '12345678${passendeCijfers('12345678', isValidCaSin).single}';
      expect(rulesIn('Referentie $geldig'), isNot(contains('ca.sin')));
      expect(rulesIn('SIN $geldig'), contains('ca.sin'));
    });

    test('staat uit zolang het pakket niet gekozen is', () {
      final geldig =
          '12345678${passendeCijfers('12345678', isValidCaSin).single}';
      expect(
        rulesIn('SIN $geldig', regions: defaultPrivacyRegions),
        isNot(contains('ca.sin')),
      );
    });
  });

  group('ca.ramq — codeert geboortedatum én geslacht', () {
    test('accepteert een geldige datum, in beide geslachtsvarianten', () {
      expect(isValidCaRamq('ABCD90021501'), isTrue);
      // Maand +50 duidt een vrouw aan, net als in het Sloveense stelsel.
      expect(isValidCaRamq('ABCD90521501'), isTrue);
    });

    test('wijst onmogelijke datums af', () {
      expect(isValidCaRamq('ABCD90131501'), isFalse); // maand 13
      expect(isValidCaRamq('ABCD90023201'), isFalse); // dag 32
      expect(isValidCaRamq('ABCD90003201'), isFalse); // maand 00
    });

    test('eist vier letters en acht cijfers', () {
      expect(isValidCaRamq('ABC900215012'), isFalse);
      expect(isValidCaRamq('ABCD9002150'), isFalse);
    });

    test('vuurt alleen met context', () {
      expect(rulesIn('RAMQ ABCD 9002 1501'), contains('ca.ramq'));
      expect(rulesIn('Code ABCD 9002 1501'), isNot(contains('ca.ramq')));
    });
  });

  group('ca.ohip', () {
    test('de implementatie discrimineert', () {
      // Zie de kop van dit bestand: dit toetst dát er precies één cijfer past,
      // niet dat Luhn het juiste algoritme is.
      expect(passendeCijfers('123456789', isValidCaOhip), hasLength(1));
    });

    test('een voorloopnul bestaat niet', () {
      expect(passendeCijfers('012345678', isValidCaOhip), isEmpty);
    });

    test('vuurt met context, ook met versieletters', () {
      final c = passendeCijfers('123456789', isValidCaOhip).single;
      expect(rulesIn('OHIP 1234-567-89$c'), contains('ca.ohip'));
      expect(rulesIn('health card 1234 567 89$c AB'), contains('ca.ohip'));
      expect(rulesIn('Artikel 1234-567-89$c'), isNot(contains('ca.ohip')));
    });
  });

  group('ca.bn', () {
    test('de programmacode telt niet mee in de checksum', () {
      final c = passendeCijfers('12345678', isValidCaBn).single;
      expect(isValidCaBn('12345678$c'), isTrue);
      expect(isValidCaBn('12345678${c}RC0001'), isTrue);
    });

    test('te kort is geen bedrijfsnummer', () {
      expect(isValidCaBn('1234567'), isFalse);
    });
  });
}
