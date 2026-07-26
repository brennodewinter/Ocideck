import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_usage.dart';
import 'package:path/path.dart' as p;

/// De afbeeldingenbibliotheek doet op deze twee antwoorden iets onomkeerbaars:
/// "0 dia's gebruiken dit" is waarop iemand een bestand weggooit, en na het
/// ontdubbelen moeten de dia's naar het behouden bestand wijzen. Een gemiste
/// verwijzing is dus een kapotte presentatie, geen schoonheidsfoutje.
void main() {
  const project = '/deck';

  // De ruimhartige variant, zoals het editorveld hem gebruikt: relatief pad
  // tegen de projectmap, absoluut pad ongemoeid.
  String? resolve(String path) =>
      p.normalize(p.isAbsolute(path) ? path : p.join(project, path));

  Deck deckOf(List<Slide> slides) =>
      Deck(title: 'D', slides: slides, projectPath: project);

  Slide text(String markdown) => Slide.create(
    SlideType.freeMarkdown,
  ).copyWith(title: 'Verhaal', customMarkdown: markdown);

  group('slideIndexesUsingImage', () {
    test('vindt een verwijzing in een afbeeldingsveld', () {
      final deck = deckOf([
        Slide.create(SlideType.bullets).copyWith(title: 'Zonder beeld'),
        Slide.create(SlideType.image).copyWith(imagePath: 'images/foto.png'),
      ]);

      expect(
        slideIndexesUsingImage(
          deck,
          p.normalize('/deck/images/foto.png'),
          resolve,
        ),
        [1],
      );
    });

    test('vindt er ook eentje in de vrije tekst', () {
      final deck = deckOf([text('Zie ![de foto](images/foto.png) hierboven.')]);

      expect(
        slideIndexesUsingImage(
          deck,
          p.normalize('/deck/images/foto.png'),
          resolve,
        ),
        [0],
      );
    });

    test('noemt een dia die hem twee keer aanhaalt maar één keer', () {
      final deck = deckOf([
        Slide.create(SlideType.image).copyWith(
          imagePath: 'images/foto.png',
          customMarkdown: 'en nog eens ![x](images/foto.png)',
        ),
      ]);

      expect(
        slideIndexesUsingImage(
          deck,
          p.normalize('/deck/images/foto.png'),
          resolve,
        ),
        [0],
      );
    });

    test('zwijgt over een pad dat niet op te lossen is', () {
      final deck = deckOf([text('![x](images/foto.png)')]);

      // Een resolver die niets teruggeeft — zo gedraagt de insluitingswacht
      // zich bij een pad dat buiten de presentatie zou wijzen.
      expect(
        slideIndexesUsingImage(
          deck,
          p.normalize('/deck/images/foto.png'),
          (_) => null,
        ),
        isEmpty,
      );
    });
  });

  group('slideWithImageReplaced', () {
    String vervang(String _) => 'images/behouden.png';

    test('zet een verwijzing in de vrije tekst om', () {
      final out = slideWithImageReplaced(
        text('Zie ![w:600 de foto](images/duplicaat.png) hierboven.'),
        p.normalize('/deck/images/duplicaat.png'),
        resolve,
        vervang,
      );

      expect(
        out.customMarkdown,
        'Zie ![w:600 de foto](images/behouden.png) hierboven.',
      );
    });

    test('zet veld en tekst tegelijk om', () {
      final slide = Slide.create(SlideType.image).copyWith(
        imagePath: 'images/duplicaat.png',
        customMarkdown: '![x](images/duplicaat.png)',
      );

      final out = slideWithImageReplaced(
        slide,
        p.normalize('/deck/images/duplicaat.png'),
        resolve,
        vervang,
      );

      expect(out.imagePath, 'images/behouden.png');
      expect(out.customMarkdown, '![x](images/behouden.png)');
    });

    test('laat een andere afbeelding met rust', () {
      final slide = text('![x](images/andere.png)');

      // Dezelfde dia terug, zodat de aanroeper geen lege bewerking in de
      // ongedaan-stapel zet.
      expect(
        identical(
          slideWithImageReplaced(
            slide,
            p.normalize('/deck/images/duplicaat.png'),
            resolve,
            vervang,
          ),
          slide,
        ),
        isTrue,
      );
    });
  });
}
