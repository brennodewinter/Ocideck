import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_dated_claims.dart';

/// De verouderingspoort voor gemeten beweringen, in **twee** richtingen.
///
/// De aanleiding staat in de kop van tool/check_dated_claims.dart: twee plekken
/// in `docs/CHECKS.md` beloofden "within ~half an hour" terwijl de meting
/// intussen op 54 minuten stond. Die claim droeg geen cijfer en geen datum —
/// een poort die alleen op `\d+ minutes` let of alleen op het register kijkt,
/// had hem allebei niet gezien.
///
/// Daarom toetst dit bestand niet alleen dat de boom vandaag schoon is, maar
/// ook dat elk van de drie faalvormen er daadwerkelijk als rood doorheen komt:
/// een anker dat verdwijnt, een meting die verloopt, en een uitdrukking die
/// erbij komt. Een groene poort die niet rood kán worden is hier al een keer
/// voor bewijs aangezien.
void main() {
  group('de boom zoals hij nu is', () {
    test('elk anker uit het register staat nog in zijn document', () {
      for (final bewering in gemetenBeweringen) {
        final bestand = File(bewering.bestand);
        expect(
          bestand.existsSync(),
          isTrue,
          reason: '${bewering.id} wijst naar ${bewering.bestand}',
        );
        expect(
          beoordeel(
            bewering,
            bestand.readAsStringSync(),
            DateTime.parse(bewering.gemetenOp),
            tegenDeKlok: true,
          ),
          Staat.vers,
          reason:
              '${bewering.id}: het anker "${bewering.anker}" is niet te vinden '
              'in ${bewering.bestand}',
        );
      }
    });

    test('het anker draagt dezelfde meetdatum als het register', () {
      // Anders lopen document en register uiteen op precies het getal waar het
      // om gaat, en meldt de poort "vers" over een datum die de lezer niet ziet.
      for (final bewering in gemetenBeweringen) {
        expect(
          bewering.anker,
          contains(bewering.gemetenOp),
          reason:
              '${bewering.id}: zet de meetdatum in het anker, zodat het '
              'document en dit register niet uiteen kunnen lopen',
        );
      }
    });

    test('elke bewaakte tekst komt overeen met de basislijn', () {
      for (final pad in looptijdBasislijn.keys) {
        final inhoud = File(pad).readAsStringSync();
        expect(
          afwijkingen(looptijdBasislijn[pad]!, looptijdenIn(inhoud)),
          isEmpty,
          reason: '$pad wijkt af van looptijdBasislijn',
        );
      }
    });

    test('de basislijn telt niet leeg — er is werkelijk iets bewaakt', () {
      // Een patroon dat door een herschrijving stil naast alles grijpt, meldt
      // nul afwijkingen en leest als groen. Dat is de faalvorm die #1911 in de
      // wachtpuntpoort opleverde: de poort zag 3 van de 129 gevallen.
      for (final pad in looptijdBasislijn.keys) {
        expect(
          looptijdenIn(File(pad).readAsStringSync()),
          isNotEmpty,
          reason: '$pad levert geen enkele treffer meer op',
        );
      }
      expect(gemetenBeweringen, isNotEmpty);
    });
  });

  group('een verdwenen anker is rood', () {
    final bewering = gemetenBeweringen.first;

    test('een document zonder het anker levert Staat.zoek', () {
      expect(
        beoordeel(
          bewering,
          'Een document dat de bewering is kwijtgeraakt.',
          DateTime.parse(bewering.gemetenOp),
          tegenDeKlok: false,
        ),
        Staat.zoek,
      );
    });

    test('een anker dat over twee regels is afgebroken telt wél mee', () {
      // Markdown wikkelt op ~78 tekens; zonder platgeslagen witruimte zou een
      // onschuldige herwikkeling de poort laten omvallen, en dan wordt hij
      // uitgezet in plaats van gevolgd.
      final gewikkeld = bewering.anker.replaceFirst(' ', '\n  ');
      expect(
        beoordeel(
          bewering,
          'tekst eromheen $gewikkeld en verder',
          DateTime.parse(bewering.gemetenOp),
          tegenDeKlok: false,
        ),
        Staat.vers,
      );
    });
  });

  group('een verlopen meting is rood', () {
    final bewering = gemetenBeweringen.first;
    final inhoud = File(bewering.bestand).readAsStringSync();
    final gemeten = DateTime.parse(bewering.gemetenOp);

    test('één dag over de houdbaarheid levert Staat.verouderd', () {
      expect(
        beoordeel(
          bewering,
          inhoud,
          gemeten.add(Duration(days: bewering.houdbaarDagen + 1)),
          tegenDeKlok: true,
        ),
        Staat.verouderd,
      );
    });

    test('op de laatste houdbare dag is hij nog vers', () {
      expect(
        beoordeel(
          bewering,
          inhoud,
          gemeten.add(Duration(days: bewering.houdbaarDagen)),
          tegenDeKlok: true,
        ),
        Staat.vers,
      );
    });

    test('zonder --tegen-de-klok zwijgt de houdbaarheid', () {
      // De structurele helft draait per PR. Zou de houdbaarheid daar meedoen,
      // dan valt op een dag een willekeurige PR om op een bewering waar de
      // indiener niets mee te maken heeft.
      expect(
        beoordeel(
          bewering,
          inhoud,
          gemeten.add(const Duration(days: 3650)),
          tegenDeKlok: false,
        ),
        Staat.vers,
      );
    });
  });

  group('een nieuwe looptijduitdrukking is rood', () {
    test('een uitdrukking erbij levert een afwijking', () {
      final basislijn = {'22 minutes': 1};
      final nu = looptijdenIn('dat kostte 22 minutes, nu nog 8 minutes');
      expect(afwijkingen(basislijn, nu), hasLength(1));
      expect(afwijkingen(basislijn, nu).single, contains('8 minutes'));
    });

    test('een uitdrukking eraf levert óók een afwijking', () {
      // Beide richtingen, om dezelfde reden als in de referentiedatapoort: een
      // afwijking betekent dat de boekhouding niet klopt, niet dat de ene kant
      // erger is dan de andere.
      expect(
        afwijkingen({'22 minutes': 2}, looptijdenIn('nog maar 22 minutes')),
        hasLength(1),
      );
    });

    test(
      'de woordvorm zonder cijfer telt mee — dat was de hele aanleiding',
      () {
        // "within ~half an hour" was de bewering die verrotte. Een patroon dat
        // alleen naar cijfers kijkt, ziet hem niet.
        expect(
          looptijdenIn('binnen half an hour'),
          containsPair('half an hour', 1),
        );
        expect(
          looptijdenIn('takes about an hour'),
          containsPair('about an hour', 1),
        );
        expect(
          looptijdenIn('an hour or so later'),
          containsPair('an hour or so', 1),
        );
      },
    );

    test('een koppelteken en een meervoud vallen op dezelfde sleutel', () {
      // "a 46-minute gate" en "46 minute" zijn dezelfde bewering; zonder deze
      // normalisatie splitst de basislijn in vormen die niemand uit elkaar wil
      // houden.
      expect(looptijdenIn('a 46-minute gate'), containsPair('46 minute', 1));
    });

    test('een gelijk gebleven tekst levert niets op', () {
      final tekst = File('CONTRIBUTING.md').readAsStringSync();
      expect(
        afwijkingen(looptijdBasislijn['CONTRIBUTING.md']!, looptijdenIn(tekst)),
        isEmpty,
      );
    });
  });
}
