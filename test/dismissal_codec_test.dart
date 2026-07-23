import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';

/// De sidecar met terzijdegelegde privacybevindingen (#651, FILE_FORMAT §6.7).
///
/// Twee dingen kunnen hier stil misgaan, en allebei de verkeerde kant op:
/// een bevinding die verborgen blijft terwijl niemand daar nog voor koos, en
/// een oordeel dat bij het samenvoegen verdwijnt. Deze toetsen gaan daarover.
void main() {
  DateTime t(int minuut) => DateTime.utc(2026, 7, 23, 12, minuut);

  PrivacyDismissal d(String rule, String commitment, DateTime at) =>
      PrivacyDismissal(ruleId: rule, commitment: commitment, at: at);

  group('commitmentFor', () {
    test('is stabiel, en hangt aan het zout', () {
      expect(
        commitmentFor('abc', 'Jan Jansen'),
        commitmentFor('abc', 'Jan Jansen'),
      );
      expect(
        commitmentFor('abc', 'Jan Jansen'),
        isNot(commitmentFor('def', 'Jan Jansen')),
        reason:
            'per deck een eigen zout, anders is te zien welke decks over '
            'dezelfde persoon gaan',
      );
      expect(
        commitmentFor('abc', 'Jan Jansen'),
        isNot(commitmentFor('abc', 'Jan Jansens')),
      );
    });

    test('draagt de waarde zelf niet', () {
      // De kern van §6.7: deze sidecar mag geen tweede kopie van een
      // persoonsgegeven worden die de verwijdering van het origineel overleeft.
      final c = commitmentFor('abc', 'Jan Jansen');
      expect(c, isNot(contains('Jan')));
      expect(c, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(c), isTrue);
    });
  });

  group('hides', () {
    test('verbergt waar voor gekozen is, en niets anders', () {
      final set = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', commitmentFor('zout', 'Jan Jansen'), t(0))],
      );
      expect(set.hides('nl.name', 'Jan Jansen'), isTrue);
      expect(set.hides('nl.name', 'Piet Pietersen'), isFalse);
      // Dezelfde waarde, andere regel: een apart oordeel.
      expect(set.hides('fin.iban', 'Jan Jansen'), isFalse);
    });

    test('een latere herroeping wint', () {
      final c = commitmentFor('zout', 'Jan Jansen');
      final set = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', c, t(0))],
        revocations: [d('nl.name', c, t(5))],
      );
      expect(set.hides('nl.name', 'Jan Jansen'), isFalse);
    });

    test('opnieuw terzijdeleggen ná een herroeping werkt', () {
      final c = commitmentFor('zout', 'Jan Jansen');
      final set = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', c, t(0)), d('nl.name', c, t(10))],
        revocations: [d('nl.name', c, t(5))],
      );
      expect(set.hides('nl.name', 'Jan Jansen'), isTrue);
    });

    test('bij een gelijk tijdstempel blijft de bevinding zichtbaar', () {
      // De faalrichting die we willen: liever een melding te veel dan een
      // persoonsgegeven dat stilletjes onderdrukt wordt.
      final c = commitmentFor('zout', 'Jan Jansen');
      final set = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', c, t(0))],
        revocations: [d('nl.name', c, t(0))],
      );
      expect(set.hides('nl.name', 'Jan Jansen'), isFalse);
    });
  });

  group('encode/decode', () {
    test('gaat heen en terug, inclusief seen_at', () {
      final origineel = DeckDismissals(
        salt: 'zout',
        dismissals: [
          PrivacyDismissal(
            ruleId: 'nl.name',
            commitment: commitmentFor('zout', 'Jan Jansen'),
            at: t(0),
            seenAtSlide: 4,
            seenAtField: 'bullets',
            seenAtFragment: 2,
          ),
        ],
        revocations: [d('fin.iban', 'aa' * 32, t(3))],
      );
      final terug = DismissalCodec.decode(
        DismissalCodec.encode(origineel)!,
        fallbackSalt: 'anders',
      );
      expect(terug.salt, 'zout');
      expect(terug.dismissals, hasLength(1));
      expect(terug.dismissals.single.seenAtSlide, 4);
      expect(terug.dismissals.single.seenAtField, 'bullets');
      expect(terug.dismissals.single.seenAtFragment, 2);
      expect(terug.dismissals.single.at, t(0));
      expect(terug.revocations, hasLength(1));
      expect(terug.hides('nl.name', 'Jan Jansen'), isTrue);
    });

    test('niets terzijdegelegd betekent geen bestand', () {
      expect(DismissalCodec.encode(const DeckDismissals(salt: 'zout')), isNull);
    });

    test('een nieuwere sidecar wordt niet geladen', () {
      // En, in de laag erboven, ook niet overschreven — dat is het contract van
      // sidecar_format.dart. Half inlezen zou de rest bij het opslaan wissen.
      final json = jsonEncode({
        'version': DismissalCodec.version + 1,
        'salt': 'zout',
        'dismissals': [
          {
            'rule': 'nl.name',
            'commitment': commitmentFor('zout', 'Jan Jansen'),
            'at': t(0).toIso8601String(),
          },
        ],
      });
      final terug = DismissalCodec.decode(json, fallbackSalt: 'nieuw');
      expect(terug.isEmpty, isTrue);
      expect(terug.hides('nl.name', 'Jan Jansen'), isFalse);
    });

    test('kapotte JSON laat de bevindingen zichtbaar', () {
      final terug = DismissalCodec.decode(
        '{niet eens json',
        fallbackSalt: 'nieuw',
      );
      expect(terug.isEmpty, isTrue);
      expect(terug.salt, 'nieuw');
    });

    test('één verhaspelde regel neemt de andere niet mee', () {
      final json = jsonEncode({
        'version': 1,
        'salt': 'zout',
        'dismissals': [
          {'rule': 'nl.name', 'at': t(0).toIso8601String()}, // geen commitment
          {'commitment': 'aa' * 32, 'at': t(0).toIso8601String()}, // geen regel
          {'rule': 'x', 'commitment': 'bb' * 32, 'at': 'geen datum'},
          {
            'rule': 'nl.name',
            'commitment': commitmentFor('zout', 'Jan Jansen'),
            'at': t(0).toIso8601String(),
          },
        ],
      });
      final terug = DismissalCodec.decode(json, fallbackSalt: 'anders');
      expect(terug.dismissals, hasLength(1));
      expect(terug.hides('nl.name', 'Jan Jansen'), isTrue);
    });
  });

  group('mergeDismissals', () {
    test('twee reviewers houden allebei hun oordeel', () {
      final a = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', 'aa' * 32, t(0))],
      );
      final b = DeckDismissals(
        salt: 'zout',
        dismissals: [d('fin.iban', 'bb' * 32, t(1))],
      );
      expect(mergeDismissals(a, b).dismissals, hasLength(2));
    });

    test('een herroeping overleeft het samenvoegen', () {
      // Dit is waarvoor de grafstenen bestaan. Zonder hen zou de herroeping
      // verdwijnen — de andere kant draagt de terzijdelegging nog — en bleef
      // de bevinding verborgen. De stille faalrichting.
      final c = commitmentFor('zout', 'Jan Jansen');
      final metHerroeping = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', c, t(0))],
        revocations: [d('nl.name', c, t(5))],
      );
      final zonder = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', c, t(0))],
      );
      expect(
        mergeDismissals(metHerroeping, zonder).hides('nl.name', 'Jan Jansen'),
        isFalse,
      );
      // En andersom net zo goed: samenvoegen is symmetrisch in uitkomst.
      expect(
        mergeDismissals(zonder, metHerroeping).hides('nl.name', 'Jan Jansen'),
        isFalse,
      );
    });

    test('bij dezelfde sleutel wint de latere', () {
      final a = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', 'aa' * 32, t(0))],
      );
      final b = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', 'aa' * 32, t(9))],
      );
      final samen = mergeDismissals(a, b);
      expect(samen.dismissals, hasLength(1));
      expect(samen.dismissals.single.at, t(9));
    });

    test('een ander zout is een ander deck, dus wij winnen', () {
      final ons = DeckDismissals(
        salt: 'zout',
        dismissals: [d('nl.name', 'aa' * 32, t(0))],
      );
      final vreemd = DeckDismissals(
        salt: 'ander',
        dismissals: [d('fin.iban', 'bb' * 32, t(1))],
      );
      // Commitments onder een ander zout betekenen hier niets; ze overnemen
      // zou onzin toevoegen die nooit ergens op matcht.
      expect(mergeDismissals(ons, vreemd).dismissals, hasLength(1));
      expect(mergeDismissals(ons, vreemd).salt, 'zout');
    });
  });
}
