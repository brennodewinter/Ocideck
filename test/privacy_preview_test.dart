import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_preview.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

/// De auteursweergave van de projectie: kan iemand vóór verzending zien wat de
/// ontvanger krijgt? Tot nu toe niet — de preview toonde het rauwe deck en de
/// projectie draaide alleen bij presenteren en exporteren, dus pas de PDF gaf
/// antwoord.
void main() {
  Slide slideWith({
    String bullet = 'Contact: jan.jansen@voorbeeld.nl',
    String imagePath = 'images/team.png',
    PrivacyDisposition? privacy,
  }) => Slide.create(SlideType.bulletsImage).copyWith(
    title: 'Contactgegevens',
    bullets: [bullet],
    imagePath: imagePath,
    privacy: privacy,
    clearPrivacy: privacy == null,
  );

  Deck deckWith(
    Slide slide, {
    PrivacyDisposition deckPrivacy = PrivacyDisposition.warn,
  }) => Deck(title: 'Test', privacy: deckPrivacy, slides: [slide]);

  group('slideIsRedacted', () {
    test('de stand van de dia wint van die van het deck', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      expect(slideIsRedacted(deckWith(slide), slide), isTrue);
    });

    test('een dia zonder eigen stand erft die van het deck', () {
      final slide = slideWith();
      expect(
        slideIsRedacted(
          deckWith(slide, deckPrivacy: PrivacyDisposition.redact),
          slide,
        ),
        isTrue,
      );
      expect(slideIsRedacted(deckWith(slide), slide), isFalse);
    });

    test('een dia mag afwijken van een redigerend deck', () {
      final slide = slideWith(privacy: PrivacyDisposition.accept);
      expect(
        slideIsRedacted(
          deckWith(slide, deckPrivacy: PrivacyDisposition.redact),
          slide,
        ),
        isFalse,
      );
    });
  });

  group('audiencePreviewOf', () {
    test('laat de gevonden gegevens zwart zien', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewOf(deckWith(slide), slide).slides.first;
      expect(shown.bullets.first, isNot(contains('jan.jansen@voorbeeld.nl')));
      expect(shown.bullets.first, contains('█'));
    });

    test('strippt álle media van de dia — dat stond nergens', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewOf(deckWith(slide), slide).slides.first;
      expect(shown.imagePath, isEmpty);
      expect(shown.mediaRedacted, isTrue);
    });

    test('blokkeert bewerken tijdens presenteren op de getoonde kopie', () {
      // Anders zou een aanvinking op de geredigeerde tekst terugschrijven naar
      // de bron.
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewOf(deckWith(slide), slide).slides.first;
      expect(shown.contentRedacted, isTrue);
    });

    test('laat de bron ongemoeid', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      audiencePreviewOf(deckWith(slide), slide).slides.first;
      expect(slide.bullets.first, contains('jan.jansen@voorbeeld.nl'));
      expect(slide.imagePath, 'images/team.png');
    });

    test('een dia die niet weggelaten wordt, blijft ongewijzigd', () {
      final slide = slideWith(privacy: PrivacyDisposition.warn);
      final shown = audiencePreviewOf(deckWith(slide), slide).slides.first;
      expect(shown.bullets.first, contains('jan.jansen@voorbeeld.nl'));
      expect(shown.imagePath, 'images/team.png');
    });

    test('projecteert één dia, niet het hele deck', () {
      // De projectie scant zelf; het hele deck scannen bij elke toetsaanslag in
      // de editor ernaast zou de preview onbruikbaar traag maken. Voor wat de
      // preview toont maakt het niets uit.
      final target = slideWith(privacy: PrivacyDisposition.redact);
      final other = Slide.create(SlideType.bullets).copyWith(
        bullets: const ['Ook hier: piet@voorbeeld.nl'],
        privacy: PrivacyDisposition.redact,
      );
      final deck = Deck(title: 'Test', slides: [target, other]);
      final shown = audiencePreviewOf(deck, target).slides.first;
      expect(shown.bullets.first, contains('█'));
      // De andere dia is niet aangeraakt: er is er maar één geprojecteerd.
      expect(other.bullets.first, contains('piet@voorbeeld.nl'));
    });
  });

  group('de preview toont hetzelfde als de export', () {
    // Dit is de aanname waar de hele publieksweergave op steunt: één dia
    // projecteren geeft voor díe dia hetzelfde als het hele deck projecteren.
    // Vandaag klopt dat — de scanner escaleert bínnen een dia — maar een
    // escalator die het deck als geheel bekijkt zou dat stil breken, en dan
    // toont de preview minder redactie dan de export. Precies de verkeerde
    // richting.
    void expectSameAsFullDeck(Deck deck) {
      final full = PrivacyProjection.forAudience(deck);
      for (var i = 0; i < deck.slides.length; i++) {
        final one = audiencePreviewOf(deck, deck.slides[i]).slides.first;
        final all = full.slides[i];
        expect(one.title, all.title, reason: 'dia $i titel');
        expect(one.subtitle, all.subtitle, reason: 'dia $i ondertitel');
        expect(one.bullets, all.bullets, reason: 'dia $i opsomming');
        expect(one.bullets2, all.bullets2, reason: 'dia $i tweede opsomming');
        expect(one.tableRows, all.tableRows, reason: 'dia $i tabel');
        expect(one.notes, all.notes, reason: 'dia $i notities');
        expect(one.quote, all.quote, reason: 'dia $i citaat');
        expect(one.imagePath, all.imagePath, reason: 'dia $i afbeelding');
        expect(one.videoPath, all.videoPath, reason: 'dia $i video');
        expect(one.audioPath, all.audioPath, reason: 'dia $i audio');
        expect(one.mediaRedacted, all.mediaRedacted, reason: 'dia $i media');
        expect(
          one.contentRedacted,
          all.contentRedacted,
          reason: 'dia $i inhoud',
        );
      }
    }

    test('over een deck met gemengde standen', () {
      expectSameAsFullDeck(
        Deck(
          title: 'Rapport',
          organization: 'Zorggroep Oost',
          slides: [
            slideWith(privacy: PrivacyDisposition.redact),
            slideWith(
              bullet: 'Piet Jansen, piet@voorbeeld.nl, 06-12345678',
              privacy: PrivacyDisposition.accept,
            ),
            Slide.create(SlideType.bullets).copyWith(
              title: 'Deelnemers',
              bullets: const [
                'a@voorbeeld.nl',
                'b@voorbeeld.nl',
                'c@voorbeeld.nl',
                'd@voorbeeld.nl',
                'e@voorbeeld.nl',
              ],
              notes: 'Intern: budget bij jan.jansen@voorbeeld.nl',
              privacy: PrivacyDisposition.redact,
            ),
            Slide.create(SlideType.table).copyWith(
              title: 'Overzicht',
              tableRows: const [
                ['Naam', 'E-mail'],
                ['Jan', 'jan@voorbeeld.nl'],
                ['Piet', 'piet@voorbeeld.nl'],
              ],
              privacy: PrivacyDisposition.redact,
            ),
          ],
        ),
      );
    });

    test('en als het deck zelf redigeert', () {
      expectSameAsFullDeck(
        Deck(
          title: 'Rapport',
          privacy: PrivacyDisposition.redact,
          slides: [
            slideWith(),
            slideWith(bullet: 'IBAN NL91ABNA0417164300', imagePath: ''),
          ],
        ),
      );
    });
  });
}
