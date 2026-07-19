// Woordgrenzen, voorvoegsels en het zwarte blok dat niets verbergt.
//
// Twee reparaties in één fase, en ze hangen samen. De matcher was een kale
// `indexOf`, dus `vog` vond de vogels. En redactie werkte op trefwoordniveau,
// dus "diagnose" werd weggelakt terwijl de naam ernaast bleef staan.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_special_rules.dart';

void main() {
  const scanner = PrivacyScanner();

  Deck deckWith(String text, {PrivacyDisposition? privacy}) => Deck(
    title: 'T',
    privacy: privacy ?? PrivacyDisposition.warn,
    slides: [
      Slide.create(SlideType.bullets).copyWith(bullets: [text]),
    ],
  );

  Set<String> rulesFor(String text) =>
      scanner.scan(deckWith(text)).findings.map((f) => f.ruleId).toSet();

  String redact(String text) => PrivacyProjection.forAudience(
    deckWith(text, privacy: PrivacyDisposition.redact),
  ).deck.slides.single.bullets.single;

  group('findPrivacyTerm', () {
    test('een korte term matcht alleen als heel woord', () {
      // `vog` in `vogels` was een echte melding in de oude matcher, en het is
      // het soort fout dat de hele controle ongeloofwaardig maakt.
      expect(findPrivacyTerm('de vogels vliegen', 'vog'), -1);
      expect(findPrivacyTerm('een vog aanvragen', 'vog'), 4);
      // Een koppelteken is een woordgrens, dus dit hoort wél te matchen.
      expect(findPrivacyTerm('hiv-positief', 'hiv'), 0);
    });

    test('een lange term matcht op woordbegin met vrij achtervoegsel', () {
      expect(findPrivacyTerm('wordt verdacht van', 'verdacht'), 6);
      expect(findPrivacyTerm('de verdachte', 'verdacht'), 3);
      expect(findPrivacyTerm('alle verdachten', 'verdacht'), 5);
    });

    test('midden in een woord matcht nooit', () {
      // Zonder deze regel vindt `raad` de voorraad.
      expect(findPrivacyTerm('de voorraad is op', 'raad'), -1);
    });

    test('accenttekens horen bij het woord', () {
      // `patiënt` is één woord; zonder dit zou `ent` op een grens lijken.
      expect(findPrivacyTerm('de patiëntnaam', 'naam'), -1);
    });

    test('een lege term vindt niets', () {
      expect(findPrivacyTerm('wat dan ook', ''), -1);
    });
  });

  group('scanner', () {
    test('de stam dekt de verbogen vormen', () {
      // "wordt verdacht van" is de gebruikelijkste formulering en werd volledig
      // gemist zolang de lijst alleen `verdachte` bevatte. Sinds de
      // persoonskoppelingspoort levert dezelfde zin er een tweede bevinding bij:
      // het predicaat wijst "Marieke" aan als persoon.
      expect(
        rulesFor('Marieke wordt verdacht van diefstal'),
        containsAll(<String>['special.criminal', 'contact.name']),
      );
      // Zonder iemand om aan te wijzen blijft het bij het trefwoord alleen.
      expect(rulesFor('Alle verdachten zijn gehoord'), {'special.criminal'});
    });

    test('een woord dat een trefwoord bevat is geen treffer', () {
      expect(rulesFor('De vogels vliegen over het weiland'), isEmpty);
    });
  });

  group('redactie van aanwijzingen', () {
    test('een los trefwoord wordt niet weggelakt', () {
      // Dit lakte eerder "diagnose" weg en liet "Jan" staan: niets verborgen,
      // en de ontvanger denkt ten onrechte dat daar iets gevoeligs stond.
      const line = 'Jan had een diagnose bij de huisarts';
      expect(redact(line), line);
    });

    test('met een persoon erbij gaat de hele mededeling weg', () {
      final out = redact('Jan, jan.jansen@politie.nl, diagnose F32.1');
      expect(out, isNot(contains('diagnose')));
      expect(out, isNot(contains('jan.jansen')));
      expect(out, contains('█'));
    });

    test('een gegeven dat zichzelf is, gaat wél weg', () {
      // Genetische notatie en een parketnummer zijn het gegeven, niet een
      // aanwijzing ernaar.
      expect(redact('Variant rs334 gevonden'), isNot(contains('rs334')));
      expect(
        redact('Zaak 01/234567-19 loopt nog'),
        isNot(contains('01/234567-19')),
      );
    });

    test('de rol reist mee door escalatie', () {
      const finding = PrivacyFinding(
        ruleId: 'special.health',
        family: PrivacyFamily.specialCategory,
        confidence: PrivacyConfidence.possible,
        slideIndex: 0,
        field: 'bullets',
        start: 0,
        end: 8,
        maskedSample: 'd…e',
        role: PrivacyTermRole.indicator,
      );
      expect(finding.isRedactable, isFalse);
      final escalated = finding.escalated(start: 0, end: 40);
      expect(escalated.role, PrivacyTermRole.indicator);
      expect(escalated.isRedactable, isTrue);
    });
  });
}
