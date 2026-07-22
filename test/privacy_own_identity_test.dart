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
      const own = OwnIdentity(['A.Bakker@eigenbureau.nl']);
      expect(own.covers('a.bakker@eigenbureau.nl'), isTrue);
      expect(own.covers('A.BAKKER@EIGENBUREAU.NL'), isTrue);
      // Een collega op hetzelfde domein is géén afzender maar een derde: dat is
      // wél een bevinding. Wie de hele organisatie wil dekken, geeft het domein op.
      expect(own.covers('iemand.anders@eigenbureau.nl'), isFalse);
    });

    test('een domein dekt elk adres eronder', () {
      // Zodat een organisatie niet elke collega hoeft op te sommen.
      const own = OwnIdentity(['andersbureau.nl']);
      expect(own.covers('j.jansen@andersbureau.nl'), isTrue);
      expect(own.covers('woordvoerder@pers.andersbureau.nl'), isTrue);
    });

    test('dekt geen ander domein', () {
      const own = OwnIdentity(['andersbureau.nl']);
      expect(own.covers('j.jansen@om.nl'), isFalse);
      expect(own.covers('j.jansen@nietandersbureau.com'), isFalse);
    });

    test('een look-alike domein wordt NIET gedekt', () {
      // Dit is de val. Een losse substring-match zou `nietandersbureau.nl` laten
      // dekken door de opgave `andersbureau.nl` — een heel andere organisatie, en de
      // bevinding zou stilletjes verdwijnen. De grens moet een punt of een
      // apenstaartje zijn.
      const own = OwnIdentity(['andersbureau.nl']);
      expect(own.covers('j.jansen@nietandersbureau.nl'), isFalse);
      expect(own.covers('x@mijnandersbureau.nl'), isFalse);
    });

    test('een lege lijst dekt niets', () {
      expect(OwnIdentity.empty.covers('wat dan ook'), isFalse);
      expect(
        const OwnIdentity(['', '   ']).covers('a.bakker@eigenbureau.nl'),
        isFalse,
      );
    });

    test('round-trip door het tekstveld', () {
      final own = OwnIdentity.fromLines(
        'a.bakker@eigenbureau.nl\n\n  eigenbureau.nl  \n',
      );
      expect(own.entries, ['a.bakker@eigenbureau.nl', 'eigenbureau.nl']);
      expect(own.toLines(), 'a.bakker@eigenbureau.nl\neigenbureau.nl');
    });
  });

  group('in de scanner', () {
    test('het eigen adres is geen bevinding', () {
      final deck = deckMet('Contact: a.bakker@eigenbureau.nl');

      expect(
        const PrivacyScanner().scan(deck).firedRules,
        contains('contact.email'),
      );
      expect(
        PrivacyScanner(
          ownIdentity: OwnIdentity.fromLines('a.bakker@eigenbureau.nl'),
        ).scan(deck).firedRules,
        isEmpty,
      );
    });

    test('het adres van iemand anders wél', () {
      final deck = deckMet(
        'Contact: a.bakker@eigenbureau.nl en j.jansen@andersbureau.nl',
      );
      final result = PrivacyScanner(
        ownIdentity: OwnIdentity.fromLines('eigenbureau.nl'),
      ).scan(deck);

      expect(result.findings, hasLength(1));
      expect(result.findings.single.ruleId, 'contact.email');
    });

    test('ook het auteursveld van het deck', () {
      // Dat veld reist mee in de PDF-properties, dus het wordt gescand — maar de
      // auteur van het deck is per definitie de afzender.
      final deck = deckMet(
        'Kwartaalcijfers',
        auteur: 'a.bakker@eigenbureau.nl',
      );

      expect(const PrivacyScanner().scan(deck).findings, hasLength(1));
      expect(
        PrivacyScanner(
          ownIdentity: OwnIdentity.fromLines('eigenbureau.nl'),
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
        'Contact: a.bakker@eigenbureau.nl of j.jansen@andersbureau.nl',
        stand: PrivacyDisposition.redact,
      );

      final out = PrivacyProjection.forAudience(
        deck,
        ownIdentity: OwnIdentity.fromLines('eigenbureau.nl'),
      );
      final bullet = out.slides.single.bullets.single;

      expect(bullet, contains('a.bakker@eigenbureau.nl'));
      expect(bullet.contains('j.jansen@andersbureau.nl'), isFalse);
      expect(out.redactionCount, 1);
    });
  });
}
