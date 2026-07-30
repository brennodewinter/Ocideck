import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/template_content_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TemplateContentService', () {
    test(
      'loads the Dutch document for nl and injects the deck title',
      () async {
        final service = TemplateContentService();
        final slides = await service.loadSlides(
          'briefing',
          languageCode: 'nl',
          deckTitle: 'Mijn presentatie',
        );
        expect(slides.first.type, SlideType.title);
        expect(slides.first.title, 'Mijn presentatie');
        expect(slides.length, 6);
        expect(slides[1].title, 'Situatie in het kort');
      },
    );

    test('loads the English document for en', () async {
      final slides = await TemplateContentService().loadSlides(
        'briefing',
        languageCode: 'en',
        deckTitle: 'My presentation',
      );
      expect(slides.first.title, 'My presentation');
      expect(slides[1].title, 'Situation in brief');
    });

    test(
      'an unsupported language falls back to the English document',
      () async {
        // Voor talen waarvoor geen sjabloonbestand bestand, valt de service
        // terug naar het Engelse document.
        final slides = await TemplateContentService().loadSlides(
          'briefing',
          languageCode: 'ja',
          deckTitle: 'My presentation',
        );
        expect(slides.first.title, 'My presentation');
        expect(slides[1].title, 'Situation in brief');
      },
    );

    test('every slide gets a fresh id per load', () async {
      final service = TemplateContentService();
      Future<Set<String>> ids() async => (await service.loadSlides(
        'briefing',
        languageCode: 'nl',
        deckTitle: 'T',
      )).map((s) => s.id).toSet();
      final first = await ids();
      final second = await ids();
      expect(first.intersection(second), isEmpty);
    });

    test('a missing document falls back to a bare title slide', () async {
      final slides = await TemplateContentService().loadSlides(
        'bestaat-niet',
        languageCode: 'nl',
        deckTitle: 'Toch een deck',
      );
      expect(slides, hasLength(1));
      expect(slides.single.type, SlideType.title);
      expect(slides.single.title, 'Toch een deck');
    });

    test('an unparseable document falls back to a bare title slide', () async {
      final service = TemplateContentService(loadAsset: (_) async => '');
      final slides = await service.loadSlides(
        'briefing',
        languageCode: 'nl',
        deckTitle: 'Kaal',
      );
      expect(slides, hasLength(1));
      expect(slides.single.title, 'Kaal');
    });

    test('procesverbetering-dmaic builds a non-empty scaffold', () async {
      final slides = await TemplateContentService().loadSlides(
        'procesverbetering-dmaic',
        languageCode: 'nl',
        deckTitle: 'Order intake',
      );
      expect(slides.first.title, 'Order intake');
      expect(slides.any((s) => s.type == SlideType.tree), isTrue);
      expect(slides.any((s) => s.type == SlideType.matrix), isTrue);
    });

    test('the real bundle serves the template assets', () async {
      // Bewaakt de pubspec-registratie van assets/templates/: rootBundle moet
      // de documenten echt kunnen leveren, niet alleen het bestandssysteem.
      final markdown = await rootBundle.loadString(
        'assets/templates/empty.nl.md',
      );
      expect(markdown, contains('# Leeg deck'));
    });
  });
}
