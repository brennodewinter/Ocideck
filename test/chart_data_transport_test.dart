// A chart may keep its data in an external file and leave only a `source`
// reference in the markdown. Every surface that hands a deck to something which
// cannot resolve that reference — the audience window, a web download — has to
// inline the data instead, or the chart arrives empty.
//
// These are regression tests: each case below shipped broken, silently.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

/// A chart slide that links `data/omzet.csv` and also carries the numbers, the
/// shape a deck has in memory after its data file has been hydrated.
Slide _linkedChartSlide() => Slide.create(SlideType.chart).copyWith(
  customMarkdown: const ChartSpec(
    type: ChartType.line,
    title: 'Omzet',
    source: 'data/omzet.csv',
    x: ['Q1', 'Q2'],
    series: [
      ChartSeries(name: '2025', data: [10, 14]),
    ],
  ).toBlock(),
);

void main() {
  group('beamer payload', () {
    test('inlines linked chart data so the audience window can draw it', () {
      final markdown = FullscreenPresenter.buildBeamerMarkdown(
        slides: [_linkedChartSlide()],
        projectPath: '/decks/demo',
        themeProfile: const ThemeProfile(),
      );

      // The beamer resolves nothing relative to disk, so the numbers themselves
      // must travel in the payload.
      final slide = MarkdownService().parseDeck(markdown)!.slides.single;
      final spec = ChartSpec.parse(slide.customMarkdown);
      expect(spec.hasInlineData, isTrue);
      expect(spec.x, ['Q1', 'Q2']);
      expect(spec.series.single.data, [10, 14]);
      // The reference survives too, so the deck stays linked to its data file.
      expect(spec.source, 'data/omzet.csv');
    });

    // The counterpart of the test above: the default (what a plain save uses)
    // strips the data. That is correct on disk, where the data file sits next
    // to the .md — and exactly what must NOT happen for the beamer.
    test(
      'the default storage form strips it, which is why the flag exists',
      () {
        final markdown = MarkdownService().generateDeck(
          Deck(title: 'Demo', slides: [_linkedChartSlide()]),
        );
        final slide = MarkdownService().parseDeck(markdown)!.slides.single;
        final spec = ChartSpec.parse(slide.customMarkdown);
        expect(spec.source, 'data/omzet.csv');
        expect(spec.hasInlineData, isFalse);
      },
    );

    test('still inlines the style profile', () {
      final markdown = FullscreenPresenter.buildBeamerMarkdown(
        slides: [Slide.create(SlideType.bullets)],
        projectPath: null,
        themeProfile: const ThemeProfile(name: 'Vigilis'),
      );
      expect(markdown, contains('ocideck_style_profile'));
    });
  });
}
