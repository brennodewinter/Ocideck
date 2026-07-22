import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_special_rules.dart';

// Een bijzonder persoonsgegeven is een mededeling, geen woord.
//
// Deze test bestaat omdat de eerste versie het mís had, en op de duurst mogelijke
// manier: ze lakte het trefwoord weg en liet de mededeling staan.
//
//     Marieke de Vries meldde zich ziek met een ████████
//
// De naam staat er nog, de ziekmelding staat er nog, en `diabetes-` staat er
// letterlijk nog. Er was niets weggehaald — er was een woord bedekt. Precies de
// fout waar dit hele ontwerp tegen is gebouwd.
void main() {
  const scanner = PrivacyScanner();

  Deck deckOf(List<String> bullets, {PrivacyDisposition? stand}) => Deck(
    title: 'D',
    slides: [
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: bullets, privacy: stand),
    ],
  );

  group('statementSpan', () {
    test('pakt de hele regel om de treffer heen', () {
      const text =
          'Marieke de Vries meldde zich ziek met een diabetes-diagnose';
      final span = statementSpan(text, text.indexOf('diagnose'), text.length);

      expect(text.substring(span.start, span.end), text);
    });

    test('maar niet meer dan die ene regel', () {
      // In een notitieveld of vrije markdown staan meer mededelingen onder
      // elkaar. Eén diagnose mag niet het hele veld zwart maken: dan wordt de
      // redactie zo lomp dat de auteur haar uitzet, en dan beschermt ze niets.
      const text = 'Agenda\nJan heeft een diagnose\nRondvraag';
      final at = text.indexOf('diagnose');
      final span = statementSpan(text, at, at + 8);

      expect(text.substring(span.start, span.end), 'Jan heeft een diagnose');
    });

    test('laat de witruimte eromheen met rust', () {
      const text = 'a\n   diagnose gesteld   \nb';
      final at = text.indexOf('diagnose');
      final span = statementSpan(text, at, at + 8);

      expect(text.substring(span.start, span.end), 'diagnose gesteld');
    });
  });

  group('de escalatie verbreedt het bereik', () {
    test('een geëscaleerd gezondheidsgegeven beslaat de hele mededeling', () {
      final result = scanner.scan(
        deckOf([
          'Contactpersoon j.jansen@andersbureau.nl',
          'Marieke de Vries meldde zich ziek met een diabetes-diagnose',
        ]),
      );

      final health = result.findings.singleWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.certain);
      expect(health.start, 0);
      expect(health.end, 59);
    });

    test('zonder persoon blijft het bereik het trefwoord', () {
      // Niet geëscaleerd betekent: er is geen gegeven om te beschermen, alleen
      // een woord. Dan is er ook geen reden om de hele zin te grijpen.
      final result = scanner.scan(
        deckOf(['Onder de AVG is een diagnose een bijzonder persoonsgegeven']),
      );

      final health = result.findings.singleWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.possible);
      expect(health.end - health.start, 'diagnose'.length);
    });

    test('ook een parketnummer neemt zijn mededeling mee', () {
      // Alleen het nummer weglakken laat "Zaak ████ tegen M. de Vries" staan —
      // en dat zij verdachte is, ís het strafrechtelijke gegeven (art. 10). Het
      // nummer is er hooguit het bewijs van.
      final out = PrivacyProjection.forAudience(
        deckOf([
          'j.jansen@andersbureau.nl',
          'Zaak 01/234567-19 tegen M. de Vries',
        ], stand: PrivacyDisposition.redact),
      );

      expect(out.slides.single.bullets[1], kRedactionToken);
    });

    test('en een genetische variant ook', () {
      final out = PrivacyProjection.forAudience(
        deckOf([
          'j.jansen@andersbureau.nl',
          'Bij Marieke is rs334 aangetroffen',
        ], stand: PrivacyDisposition.redact),
      );

      expect(out.slides.single.bullets[1], kRedactionToken);
    });

    test('het gemaskeerde voorbeeld blijft het trefwoord', () {
      // De auteur moet kunnen zien wáárom er iets weggaat. "M…e" (de hele zin
      // gemaskeerd) zegt niets; het woord dat vuurde wél.
      //
      // Sinds fase 12 is dat "diabetes" en niet "diagnose", en dat is de winst
      // van het gewicht uit het lexicon: beide staan in deze zin, maar
      // "diagnose" valt in elke projectvergadering terwijl "diabetes" geen
      // tweede betekenis heeft. De melding wijst nu het gegeven aan in plaats
      // van het woord dat ernaar verwijst.
      final result = scanner.scan(
        deckOf([
          'j.jansen@andersbureau.nl',
          'Marieke de Vries heeft een diabetes-diagnose',
        ]),
      );

      final health = result.findings.singleWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.maskedSample, 'd…s');
    });
  });

  group('en dus verdwijnt de mededeling uit de projectie', () {
    test('naam én aandoening zijn weg, niet alleen het trefwoord', () {
      // De regressietest van het echte geval: dit is wat er op het scherm stond.
      final out = PrivacyProjection.forAudience(
        deckOf([
          'Contactpersoon j.jansen@andersbureau.nl',
          'Marieke de Vries meldde zich ziek met een diabetes-diagnose',
        ], stand: PrivacyDisposition.redact),
      );

      final bullet = out.slides.single.bullets[1];
      expect(bullet.contains('Marieke'), isFalse);
      expect(bullet.contains('de Vries'), isFalse);
      expect(bullet.contains('diabetes'), isFalse);
      expect(bullet.contains('ziek'), isFalse);
      expect(bullet, kRedactionToken);
    });

    test('de belendende bullet blijft leesbaar', () {
      final out = PrivacyProjection.forAudience(
        deckOf([
          'j.jansen@andersbureau.nl',
          'Marieke de Vries heeft een diabetes-diagnose',
          'Herhaaltest over twee weken',
        ], stand: PrivacyDisposition.redact),
      );

      expect(out.slides.single.bullets[2], 'Herhaaltest over twee weken');
    });
  });
}
