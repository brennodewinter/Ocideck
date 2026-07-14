import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// De eigen-identiteitslijst.
//
// De grootste praktische vals-positieven-bron van de hele scanner is de auteur
// zelf: zijn naam op de titelslide, zijn adres in de footer, zijn nummer op de
// contactslide. Dat is geen bevinding maar de afzender — en zonder deze lijst
// vuurt vrijwel élk deck onterecht, op de ene slide die er altijd in zit.
void main() {
  Deck deckMet(String tekst, {String? auteur, PrivacyDisposition? stand}) =>
      Deck(
        title: 'D',
        author: auteur ?? '',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: [tekst], privacy: stand),
        ],
      );

  group('covers', () {
    test('exacte match, hoofdletterongevoelig', () {
      const own = OwnIdentity(['Brenno@dewinter.com']);
      expect(own.covers('brenno@dewinter.com'), isTrue);
      expect(own.covers('BRENNO@DEWINTER.COM'), isTrue);
      // Een collega op hetzelfde domein is géén afzender maar een derde: dat is
      // wél een bevinding. Wie de hele organisatie wil dekken, geeft het domein op.
      expect(own.covers('iemand.anders@dewinter.com'), isFalse);
    });

    test('een domein dekt elk adres eronder', () {
      // Zodat een organisatie niet elke collega hoeft op te sommen.
      const own = OwnIdentity(['politie.nl']);
      expect(own.covers('j.jansen@politie.nl'), isTrue);
      expect(own.covers('woordvoerder@pers.politie.nl'), isTrue);
    });

    test('dekt geen ander domein', () {
      const own = OwnIdentity(['politie.nl']);
      expect(own.covers('j.jansen@om.nl'), isFalse);
      expect(own.covers('j.jansen@nietpolitie.com'), isFalse);
    });

    test('een look-alike domein wordt NIET gedekt', () {
      // Dit is de val. Een losse substring-match zou `nietpolitie.nl` laten
      // dekken door de opgave `politie.nl` — een heel andere organisatie, en de
      // bevinding zou stilletjes verdwijnen. De grens moet een punt of een
      // apenstaartje zijn.
      const own = OwnIdentity(['politie.nl']);
      expect(own.covers('j.jansen@nietpolitie.nl'), isFalse);
      expect(own.covers('x@mijnpolitie.nl'), isFalse);
    });

    test('een lege lijst dekt niets', () {
      expect(OwnIdentity.empty.covers('wat dan ook'), isFalse);
      expect(
        const OwnIdentity(['', '   ']).covers('brenno@dewinter.com'),
        isFalse,
      );
    });

    test('round-trip door het tekstveld', () {
      final own = OwnIdentity.fromLines(
        'brenno@dewinter.com\n\n  dewinter.com  \n',
      );
      expect(own.entries, ['brenno@dewinter.com', 'dewinter.com']);
      expect(own.toLines(), 'brenno@dewinter.com\ndewinter.com');
    });
  });

  group('in de scanner', () {
    test('het eigen adres is geen bevinding', () {
      final deck = deckMet('Contact: brenno@dewinter.com');

      expect(
        const PrivacyScanner().scan(deck).firedRules,
        contains('contact.email'),
      );
      expect(
        PrivacyScanner(
          ownIdentity: OwnIdentity.fromLines('brenno@dewinter.com'),
        ).scan(deck).firedRules,
        isEmpty,
      );
    });

    test('het adres van iemand anders wél', () {
      final deck = deckMet(
        'Contact: brenno@dewinter.com en j.jansen@politie.nl',
      );
      final result = PrivacyScanner(
        ownIdentity: OwnIdentity.fromLines('dewinter.com'),
      ).scan(deck);

      expect(result.findings, hasLength(1));
      expect(result.findings.single.ruleId, 'contact.email');
    });

    test('ook het auteursveld van het deck', () {
      // Dat veld reist mee in de PDF-properties, dus het wordt gescand — maar de
      // auteur van het deck is per definitie de afzender.
      final deck = deckMet('Kwartaalcijfers', auteur: 'brenno@dewinter.com');

      expect(const PrivacyScanner().scan(deck).findings, hasLength(1));
      expect(
        PrivacyScanner(
          ownIdentity: OwnIdentity.fromLines('dewinter.com'),
        ).scan(deck).isEmpty,
        isTrue,
      );
    });
  });

  group('in de projectie', () {
    test('het eigen adres wordt niet weggeredigeerd', () {
      // Zwart in de export zetten zou de contactslide onbruikbaar maken — en die
      // staat er in vrijwel elk deck in.
      final deck = deckMet(
        'Contact: brenno@dewinter.com of j.jansen@politie.nl',
        stand: PrivacyDisposition.redact,
      );

      final out = PrivacyProjection.forAudience(
        deck,
        ownIdentity: OwnIdentity.fromLines('dewinter.com'),
      );
      final bullet = out.slides.single.bullets.single;

      expect(bullet, contains('brenno@dewinter.com'));
      expect(bullet.contains('j.jansen@politie.nl'), isFalse);
      expect(out.redactionCount, 1);
    });
  });
}
