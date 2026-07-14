import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_phone_rules.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// contact.phone.
//
// De helft van deze test gaat over wat de regel NIET mag vinden, en dat is geen
// evenwichtsoefening maar de kern: een telefoonnummer is een reeks cijfers, en
// dat is een ordernummer ook. Een regel die op elk lang getal afgaat, wordt
// uitgezet — en detecteert daarna niets meer.
void main() {
  PrivacyScanResult scan(List<String> bullets, {OwnIdentity? own}) =>
      PrivacyScanner(ownIdentity: own ?? OwnIdentity.empty).scan(
        Deck(
          title: 'D',
          slides: [Slide.create(SlideType.bullets).copyWith(bullets: bullets)],
        ),
      );

  group('E.164 — de internationale vorm', () {
    test('een Nederlands mobiel nummer is zeker', () {
      final result = scan(['Bel me op +31 6 2468 1357']);
      final phone = result.findings.singleWhere(
        (f) => f.ruleId == 'contact.phone',
      );

      expect(phone.confidence, PrivacyConfidence.certain);
      expect(phone.family, PrivacyFamily.contact);
    });

    test('en dat geldt voor heel Europa, niet alleen voor ons', () {
      for (final number in [
        '+49 30 12345678', // DE
        '+33 6 12 34 56 78', // FR
        '+34 612 345 678', // ES
        '+39 320 1234567', // IT
        '+48 512 345 678', // PL
        '+353 86 123 4567', // IE
        '+372 5123 4567', // EE
      ]) {
        expect(
          scan(['Contact $number']).firedRules,
          contains('contact.phone'),
          reason: number,
        );
      }
    });

    test('een niet-toegekend landnummer is geen telefoonnummer', () {
      // Zonder de landnummerlijst zou élk getal met een plusteken ervoor een
      // telefoonnummer heten. Dat is geen validatie, dat is een aanname.
      expect(isValidE164('+999 123 4567'), isFalse);
      expect(isValidE164('+0 123 456 789'), isFalse);
    });

    test('te kort en te lang vallen af', () {
      expect(isValidE164('+31 6 24'), isFalse); // abonneenummer te kort
      expect(isValidE164('+31 62468135700000'), isFalse); // 16 cijfers
      expect(isValidE164('+31 6246813570000'), isTrue); // 15 is de E.164-grens
    });
  });

  group('de nationale vorm', () {
    test('met een scheidingsteken is het waarschijnlijk', () {
      final result = scan(['Contactpersoon, mobiel 06-24681357']);
      final phone = result.findings.singleWhere(
        (f) => f.ruleId == 'contact.phone',
      );

      expect(phone.confidence, PrivacyConfidence.likely);
    });

    test('ook een vast nummer met spaties', () {
      expect(
        scan(['Receptie 020 123 4567']).firedRules,
        contains('contact.phone'),
      );
    });

    test('kaal vuurt alleen met een contextwoord', () {
      // `0624681357` kaal is niet te onderscheiden van een oud
      // bankrekeningnummer. Het contextwoord is het verschil.
      expect(
        scan(['Referentie 0624681357']).firedRules,
        isNot(contains('contact.phone')),
      );
      expect(
        scan(['Telefoon 0624681357']).firedRules,
        contains('contact.phone'),
      );
    });
  });

  group('en dit mag het allemaal NIET vinden', () {
    test('een datum', () {
      // Acht cijfers, streepjes, een nul voorop — precies de vorm van een
      // nationaal nummer, op de lengte na. Vandaar de ondergrens van negen.
      for (final text in [
        '01-01-2024',
        '09-11-2001',
        'Gepland op 05-03-2026',
      ]) {
        expect(
          scan([text]).firedRules,
          isNot(contains('contact.phone')),
          reason: text,
        );
      }
    });

    test('een ISBN', () {
      // `0-306-40615-2`: nul voorop, streepjes, tien cijfers. De eis dat er
      // achter de nul een cijfer staat (`0\d`) houdt hem buiten.
      expect(
        scan(['ISBN 0-306-40615-2']).firedRules,
        isNot(contains('contact.phone')),
      );
    });

    test('een bedrag, een versienummer, een tijdstip', () {
      for (final text in [
        'Begroting: 1.234.567 euro',
        'Versie 10.4.2 van de app',
        'Aanvang 09:30 uur',
        'Omzet 2.450.000 in 2024',
      ]) {
        expect(
          scan([text]).firedRules,
          isNot(contains('contact.phone')),
          reason: text,
        );
      }
    });

    test('en de gereserveerde "drama"-nummers ook niet', () {
      // De example.com van de telefonie. Ze staan per definitie in documentatie —
      // ons eigen ontwerpdocument noemt het Berlijnse nummer als voorbeeld, en de
      // corpustest ving deze regel daar prompt op.
      for (final number in [
        '+49 30 23125 45', // DE, Bundesnetzagentur
        '+44 7700 900123', // UK mobiel, Ofcom
        '020 7946 0123', // UK Londen
        '+1 212 555 0134', // NANP
        '0000000000', // een reeks zonder informatie
      ]) {
        expect(
          scan(['Bel $number']).firedRules,
          isNot(contains('contact.phone')),
          reason: number,
        );
      }
    });

    test('een ordernummer zonder contextwoord', () {
      expect(
        scan(['Order 0123456789 is verwerkt']).firedRules,
        isNot(contains('contact.phone')),
      );
    });

    test('en het eigen nummer van de auteur al helemaal niet', () {
      // De contactslide van de afzender is geen bevinding.
      final result = scan([
        'Vragen? Bel +31 6 2468 1357',
      ], own: OwnIdentity(const ['+31624681357']));
      expect(result.firedRules, isNot(contains('contact.phone')));
    });
  });

  test('en het nummer verdwijnt uit de projectie', () {
    // Waar het uiteindelijk om gaat: gevonden is niet genoeg, het moet ook weg.
    final out = PrivacyProjection.forAudience(
      Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            bullets: ['Contactpersoon, mobiel 06-24681357'],
            privacy: PrivacyDisposition.redact,
          ),
        ],
      ),
    );

    expect(out.slides.single.bullets.single.contains('24681357'), isFalse);
    expect(out.redactionCount, 1);
  });

  test('het landnummer wordt prefixvrij herkend', () {
    expect(callingCodeOf('31624681357'), '31');
    expect(callingCodeOf('12125551234'), '1');
    expect(callingCodeOf('35386123456'), '353');
    expect(callingCodeOf('99912345678'), isNull);
  });
}
