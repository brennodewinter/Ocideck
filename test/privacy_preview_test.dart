import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_preview.dart';

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

  group('audiencePreviewSlide', () {
    test('laat de gevonden gegevens zwart zien', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewSlide(deckWith(slide), slide);
      expect(shown.bullets.first, isNot(contains('jan.jansen@voorbeeld.nl')));
      expect(shown.bullets.first, contains('█'));
    });

    test('strippt álle media van de dia — dat stond nergens', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewSlide(deckWith(slide), slide);
      expect(shown.imagePath, isEmpty);
      expect(shown.mediaRedacted, isTrue);
    });

    test('blokkeert bewerken tijdens presenteren op de getoonde kopie', () {
      // Anders zou een aanvinking op de geredigeerde tekst terugschrijven naar
      // de bron.
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      final shown = audiencePreviewSlide(deckWith(slide), slide);
      expect(shown.contentRedacted, isTrue);
    });

    test('laat de bron ongemoeid', () {
      final slide = slideWith(privacy: PrivacyDisposition.redact);
      audiencePreviewSlide(deckWith(slide), slide);
      expect(slide.bullets.first, contains('jan.jansen@voorbeeld.nl'));
      expect(slide.imagePath, 'images/team.png');
    });

    test('een dia die niet weggelaten wordt, blijft ongewijzigd', () {
      final slide = slideWith(privacy: PrivacyDisposition.warn);
      final shown = audiencePreviewSlide(deckWith(slide), slide);
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
      final shown = audiencePreviewSlide(deck, target);
      expect(shown.bullets.first, contains('█'));
      // De andere dia is niet aangeraakt: er is er maar één geprojecteerd.
      expect(other.bullets.first, contains('piet@voorbeeld.nl'));
    });
  });
}
