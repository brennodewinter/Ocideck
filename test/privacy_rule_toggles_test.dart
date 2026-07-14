import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// Per-regel uitschakelen: de ontsnappingsklep.
//
// Wie één regel te luid vindt, moet chirurgisch kunnen ingrijpen. Zonder die
// klep is "de hele controle uitzetten" de enige uitweg, en dat is in de praktijk
// onomkeerbaar: wie hem eenmaal uit heeft, zet hem niet meer aan.
void main() {
  Deck deckMet(String tekst, {PrivacyDisposition? stand}) => Deck(
    title: 'D',
    slides: [
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: [tekst], privacy: stand),
    ],
  );

  group('een uitgezette regel vuurt niet', () {
    test('de regel verdwijnt uit de bevindingen', () {
      final deck = deckMet('BSN 728398242 en mail j.jansen@politie.nl');

      expect(
        const PrivacyScanner().scan(deck).firedRules,
        containsAll(<String>['nl.bsn', 'contact.email']),
      );
      expect(
        const PrivacyScanner(disabledRules: {'nl.bsn'}).scan(deck).firedRules,
        equals(<String>{'contact.email'}),
      );
    });

    test('een uitgezette identificator escaleert ook niets meer', () {
      // De filtering gebeurt vóór de co-occurrence-escalator. Zou dat andersom
      // zijn, dan trok een uitgezet BSN nog steeds het woord "diagnose" omhoog —
      // en dan werkt de knop half.
      final deck = deckMet('BSN 728398242 — diagnose vastgesteld');

      final zonder = const PrivacyScanner(disabledRules: {'nl.bsn'}).scan(deck);
      final health = zonder.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.possible);
      expect(zonder.certain, isEmpty);
    });
  });

  group('de standaard-uitgezette regels', () {
    test('politiek, etniciteit en seksuele geaardheid staan standaard uit', () {
      expect(
        defaultDisabledPrivacyRules,
        containsAll(<String>[
          'special.politics',
          'special.ethnicity',
          'special.sexlife',
        ]),
      );
    });

    test('maar ze bestaan wél, en zijn aan te zetten', () {
      final deck = deckMet('etnische afkomst van de betrokkene');

      // Standaard uit: stil.
      expect(
        PrivacyScanner(
          disabledRules: defaultDisabledPrivacyRules,
        ).scan(deck).firedRules,
        isEmpty,
      );
      // Aangezet: hij vuurt.
      expect(
        const PrivacyScanner().scan(deck).firedRules,
        contains('special.ethnicity'),
      );
    });
  });

  group('uitzetten geldt óók voor redactie — en dat is het punt', () {
    // Dit is het principiële verschil met de hoofdschakelaar, en het verdient een
    // test omdat het contra-intuïtief lijkt:
    //
    //   * de hoofdschakelaar zegt "val me niet lastig". Geen oordeel over de
    //     inhoud, dus een deck op `redact` blijft redigeren;
    //   * een uitgezette regel zegt "deze regel heeft het MÍS over mijn inhoud".
    //     Dat ís een oordeel, en het honoreren betekent: niet wegredigeren.
    //
    // Iemand die nl.bsn uitzet omdat zijn ordernummers erop afgaan, wil die
    // ordernummers niet zwart in zijn export terugzien.
    test('een uitgezette regel wordt niet geredigeerd', () {
      final deck = deckMet(
        'BSN 728398242 en mail j.jansen@politie.nl',
        stand: PrivacyDisposition.redact,
      );

      final zonder = PrivacyProjection.forAudience(
        deck,
        disabledRules: const {'nl.bsn'},
      );
      final bullet = zonder.slides.single.bullets.single;

      // Het BSN blijft staan: de gebruiker heeft gezegd dat die regel er naast zit.
      expect(bullet, contains('728398242'));
      // Het e-mailadres gaat wél weg.
      expect(bullet.contains('j.jansen@politie.nl'), isFalse);
      expect(zonder.redactionCount, 1);
    });

    test('zonder uitgezette regels wordt alles geredigeerd', () {
      final deck = deckMet(
        'BSN 728398242 en mail j.jansen@politie.nl',
        stand: PrivacyDisposition.redact,
      );
      final alles = PrivacyProjection.forAudience(deck);

      expect(alles.slides.single.bullets.single.contains('728398242'), isFalse);
      expect(alles.redactionCount, 2);
    });

    test('de handmatige markering werkt altijd, ook met alles uit', () {
      // De laatste vangnet: wat de auteur zelf markeert, gaat er hoe dan ook uit.
      // Anders zou "alle regels uit" een stille lek zijn.
      final deck = deckMet('adres [[Kalverstraat 12]]');
      final out = PrivacyProjection.forAudience(
        deck,
        disabledRules: const {'nl.bsn', 'contact.email', 'fin.iban'},
      );
      expect(
        out.slides.single.bullets.single.contains('Kalverstraat'),
        isFalse,
      );
    });
  });
}
