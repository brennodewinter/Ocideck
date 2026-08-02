import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ocideck/models/improvement_y01.dart';
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

    test(
      'procesverbetering-dmaic loads the requested localized asset',
      () async {
        final requested = <String>[];
        final service = TemplateContentService(
          loadAsset: (key) async {
            requested.add(key);
            if (key != 'assets/templates/procesverbetering-dmaic.en.md') {
              throw Exception('unexpected asset: $key');
            }
            return '''
---
marp: true
ocideck_format: 1
theme: ocideck
title: "DMAIC from the asset"
language: en
ocideck_improvement_framework: dmaic
---

<!-- _class: title -->

# DMAIC from the asset

---

<!-- _class: section -->

# Localized asset marker
''';
          },
        );

        final slides = await service.loadSlides(
          'procesverbetering-dmaic',
          languageCode: 'en',
          deckTitle: 'Order intake',
        );

        expect(requested, ['assets/templates/procesverbetering-dmaic.en.md']);
        expect(slides.first.title, 'Order intake');
        expect(slides[1].title, 'Localized asset marker');
      },
    );

    test('procesverbetering-dmaic uses the real German bundle', () async {
      final slides = await TemplateContentService().loadSlides(
        'procesverbetering-dmaic',
        languageCode: 'de',
        deckTitle: 'Auftragsannahme',
      );

      expect(slides.first.title, 'Auftragsannahme');
      expect(slides.map((slide) => slide.title), contains('Definieren'));
      expect(slides.map((slide) => slide.title), contains('Projektcharter'));
      expect(slides.map((slide) => slide.title), isNot(contains('Define')));
    });

    test('procesverbetering-sipoc loads the typed matrix template', () async {
      final slides = await TemplateContentService().loadSlides(
        'procesverbetering-sipoc',
        languageCode: 'nl',
        deckTitle: 'Orderafhandeling',
      );
      final sipoc = slides.singleWhere((s) => s.type == SlideType.matrix);
      expect(slides.first.title, 'Orderafhandeling');
      expect(sipoc.improvementTemplateId, 'sipoc');
    });

    test(
      'entered Y-01 replaces only the CTQ root and keeps its branches',
      () async {
        final slides = await TemplateContentService().loadSlides(
          'procesverbetering-dmaic',
          languageCode: 'nl',
          deckTitle: 'Orderintake',
        );
        final before = slides.singleWhere(
          (slide) => slide.improvementTemplateId == 'ctq-tree',
        );

        final seeded = applyImprovementY01ToSlides(
          slides,
          const ImprovementY01Metric(name: '  Doorlooptijd orderintake  '),
        );
        final after = seeded.singleWhere(
          (slide) => slide.improvementTemplateId == 'ctq-tree',
        );

        expect(after.bullets.first, 'Doorlooptijd orderintake — **Y-01**');
        expect(after.bullets.skip(1), before.bullets.skip(1));
        expect(before.bullets.first, isNot(after.bullets.first));
      },
    );

    test(
      'empty Y-01 or a deck without CTQ leaves slide content unchanged',
      () async {
        String contentOf(List<Slide> slides) => slides
            .map(
              (slide) => [
                slide.type.name,
                slide.title,
                ...slide.bullets,
                ...slide.tableRows.expand((row) => row),
              ].join('\u001f'),
            )
            .join('\u001e');

        final dmaic = await TemplateContentService().loadSlides(
          'procesverbetering-dmaic',
          languageCode: 'nl',
          deckTitle: 'Orderintake',
        );
        expect(
          contentOf(
            applyImprovementY01ToSlides(dmaic, ImprovementY01Metric.empty),
          ),
          contentOf(dmaic),
        );

        final briefing = await TemplateContentService().loadSlides(
          'briefing',
          languageCode: 'nl',
          deckTitle: 'Briefing',
        );
        expect(
          contentOf(
            applyImprovementY01ToSlides(
              briefing,
              const ImprovementY01Metric(name: 'Doorlooptijd'),
            ),
          ),
          contentOf(briefing),
        );
      },
    );

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
