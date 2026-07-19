// De tweede lichting Europese persoonsnummers (OCIWACHT §3-A).
//
// Elf landen erbij, en op één na dragen ze allemaal hun eigen controlecijfer.
// Dat maakt de test hier anders dan bij de regels zonder checksum: er is een
// **eigenschap** te toetsen die niet van een geheugensteun afhangt.
//
// Die eigenschap is dat het algoritme *discrimineert*. Voor een gegeven
// voorloop hoort er precies één controlewaarde te bestaan die erdoorheen komt —
// niet nul (dan rekent het verkeerd) en niet meerdere (dan controleert het
// niets). Dat is te meten zonder gepubliceerde voorbeeldnummers, en dus zonder
// het risico dat de test net zo verkeerd is als de code.
//
// Voor `dk.cpr` geldt het omgekeerde, en met opzet: dat nummer hééft sinds 2007
// geen controlecijfer meer, dus daar horen álle tien de varianten door te
// komen. Vandaar de contextwoordeis.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_checksums_eu.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesIn(String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  /// Hoeveel van [candidates] het algoritme accepteert.
  int accepted(List<String> candidates, bool Function(String) validate) =>
      candidates.where(validate).length;

  group('elk algoritme laat precies één controlewaarde door', () {
    test('at.svnr', () {
      // Het controlecijfer staat op positie 4, niet aan het eind — een detail
      // dat je één keer fout doet. Vier van de tweeëndertig voorlopen hebben
      // géén geldig cijfer: daar komt de mod-11 op 10 uit, en zulke nummers
      // worden niet uitgegeven. Nooit meer dan één.
      var withOne = 0;
      for (final serial in ['123', '456', '789', '012']) {
        for (final date in ['150875', '010190', '311299', '290284']) {
          final n = accepted([
            for (var c = 0; c < 10; c++) '$serial$c$date',
          ], isValidAtSvnr);
          expect(n, lessThanOrEqualTo(1), reason: '$serial/$date gaf $n');
          if (n == 1) withOne++;
        }
      }
      expect(withOne, greaterThan(10));
    });

    test('ch.ahv', () {
      expect(
        accepted([for (var c = 0; c < 10; c++) '756123456789$c'], isValidChAhv),
        1,
      );
    });

    test('cz.rodne_cislo', () {
      expect(
        accepted([
          for (var c = 0; c < 10; c++) '840512123$c',
        ], isValidCzSkRodneCislo),
        1,
      );
    });

    test('gr.amka', () {
      expect(
        accepted([for (var c = 0; c < 10; c++) '1503851234$c'], isValidGrAmka),
        1,
      );
    });

    test('hu.taj — en waarom één op tien te zwak is', () {
      expect(
        accepted([for (var c = 0; c < 10; c++) '12345678$c'], isValidHuTaj),
        1,
      );
      // Precies één op tien is het probleem, niet het bewijs. Negen cijfers met
      // alleen een mod-10 en zonder datum erin laat elk tiende klantnummer door,
      // en dat is zwakker dan de 11-proef van het BSN. Vandaar de contextwoordeis
      // hieronder — zonder die eis ging de corpustest meteen af op
      // "Klantnummer 847362910".
      expect(rulesIn('Klantnummer 847362910'), isEmpty);
      expect(rulesIn('TAJ-szám 123456788'), contains('hu.taj'));
    });

    test('ie.pps — één letter uit drieëntwintig', () {
      expect(
        accepted([
          for (final l in 'WABCDEFGHIJKLMNOPQRSTUV'.split('')) '1234567$l',
        ], isValidIePps),
        1,
      );
    });

    test('no.fodselsnummer — één paar uit honderd', () {
      // Twee controlecijfers, dus het zoekbereik is honderd en niet tien.
      final all = <String>[
        for (var a = 0; a < 10; a++)
          for (var b = 0; b < 10; b++) '010185123$a$b',
      ];
      expect(accepted(all, isValidNoFodselsnummer), 1);
    });

    test('si.emso', () {
      expect(
        accepted([
          for (var c = 0; c < 10; c++) '010100650000$c',
        ], isValidSiEmso),
        1,
      );
    });
  });

  group('de datum in het nummer telt mee', () {
    test('een onmogelijke maand valt af', () {
      expect(isValidGrAmka('15138512347'), isFalse);
      expect(isValidSiEmso('0113006500006'), isFalse);
      expect(isValidNoFodselsnummer('01138512366'), isFalse);
    });

    test('de Tsjechische maandcodering voor vrouwen (+50) wordt gelezen', () {
      // Een vrouw geboren in mei krijgt maand 55. Zonder die correctie zou
      // elk vrouwennummer op de datumcontrole stranden.
      final vrouw = [
        for (var c = 0; c < 10; c++) '845512123$c',
      ].where(isValidCzSkRodneCislo);
      expect(vrouw, hasLength(1));
    });
  });

  group('dk.cpr — het nummer zonder controlecijfer', () {
    test('alle tien de varianten komen erdoor, en dat hoort', () {
      // De mod-11 is in 2007 losgelaten omdat de nummers opraakten. Erop
      // controleren zou echte nummers afwijzen.
      expect(
        accepted([for (var c = 0; c < 10; c++) '150385123$c'], isValidDkCpr),
        10,
      );
    });

    test('daarom is een contextwoord verplicht', () {
      expect(rulesIn('Referentie 1503851234'), isEmpty);
      expect(rulesIn('CPR-nr 150385-1234'), contains('dk.cpr'));
    });

    test('en komt het nooit hoger dan waarschijnlijk', () {
      final f = scanner
          .scan(
            Deck(
              title: 'Deck',
              slides: [
                Slide.create(
                  SlideType.bullets,
                ).copyWith(bullets: ['CPR 150385-1234']),
              ],
            ),
          )
          .findings
          .firstWhere((x) => x.ruleId == 'dk.cpr');
      expect(f.confidence, PrivacyConfidence.likely);
    });
  });

  group('in de scanner', () {
    test('de nieuwe nummers worden gevonden', () {
      expect(rulesIn('AHV 756.1234.5678.97'), contains('ch.ahv'));
      expect(rulesIn('PPS 1234567T'), contains('ie.pps'));
      expect(rulesIn('EMŠO 0101006500006'), contains('si.emso'));
      expect(rulesIn('Rodné číslo 840512/1230'), contains('cz.rodne_cislo'));
    });

    test('een willekeurig getal van dezelfde lengte niet', () {
      expect(rulesIn('Order 756123456789012'), isEmpty);
      expect(rulesIn('Referentie 0101006500001'), isEmpty);
    });

    test('ze hangen aan hun landpakket', () {
      const zonderIe = PrivacyScanner(regions: {'nl', 'de'});
      expect(
        zonderIe
            .scan(
              Deck(
                title: 'Deck',
                slides: [
                  Slide.create(
                    SlideType.bullets,
                  ).copyWith(bullets: ['PPS 1234567T']),
                ],
              ),
            )
            .firedRules,
        isEmpty,
      );
    });
  });
}
