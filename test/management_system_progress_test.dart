import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/control_status_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/management_system_artefacts.dart';
import 'package:ocideck/services/management_system_progress.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Slide _controlSlide(String heading, List<ControlStatus> statuses) =>
    Slide.create(SlideType.controlStatus).copyWith(
      title: heading,
      tableRows: ControlStatusSpec(
        heading: heading,
        rows: [
          for (var i = 0; i < statuses.length; i++)
            ControlStatusRow(id: '$heading.$i', status: statuses[i]),
        ],
      ).toTableRows(),
    );

void main() {
  group('deckManagementSystemProgress', () {
    test('rolls up per section and totals, excluding not-applicable', () {
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.title),
          _controlSlide('A.5', const [
            ControlStatus.implemented,
            ControlStatus.implemented,
            ControlStatus.partial,
            ControlStatus.notApplicable,
          ]),
          _controlSlide('A.6', const [
            ControlStatus.implemented,
            ControlStatus.notStarted,
          ]),
        ],
      );
      final p = deckManagementSystemProgress(deck);
      expect(p.sections, hasLength(2));
      expect(p.sections[0].heading, 'A.5');
      expect(p.sections[0].applicable, 3);
      expect(p.sections[0].implemented, 2);
      expect(p.sections[0].partial, 1);
      expect(p.sections[0].progressPercent, 67);
      // Totals across both sections.
      expect(p.total, 6);
      expect(p.applicable, 5);
      expect(p.implemented, 3);
      expect(p.progressPercent, 60);
    });

    test('empty when the deck has no controlStatus slides', () {
      final p = deckManagementSystemProgress(
        Deck(title: 'D', slides: [Slide.create(SlideType.title)]),
      );
      expect(p.isEmpty, isTrue);
      expect(p.progressPercent, 0);
    });
  });

  group('generateManagementSystemOverview', () {
    int gen(DeckNotifier n) => generateManagementSystemOverview(
      n,
      overviewTitle: 'Voortgang',
      sectionHeader: 'Sectie',
      applicableHeader: 'Van toepassing',
      implementedHeader: 'Geïmplementeerd',
      progressHeader: 'Voortgang',
      totalLabel: 'Totaal',
    );

    test('inserts a derived overview table and refreshes it in place', () {
      final n = _notifier()
        ..loadDeck(
          Deck(
            title: 'D',
            slides: [
              Slide.create(SlideType.title),
              _controlSlide('A.5', const [
                ControlStatus.implemented,
                ControlStatus.implemented,
                ControlStatus.notStarted,
              ]),
            ],
          ),
        );

      expect(gen(n), 1);
      var overviews = n.state.deck!.slides
          .where((s) => s.type == SlideType.table && s.title == 'Voortgang')
          .toList();
      expect(overviews, hasLength(1));
      // Header + one section row + totals row.
      expect(overviews.single.tableRows, [
        ['Sectie', 'Van toepassing', 'Geïmplementeerd', 'Voortgang'],
        ['A.5', '3', '2', '67%'],
        ['Totaal', '3', '2', '67%'],
      ]);

      // Idempotent: a second run refreshes in place, never a second overview.
      expect(gen(n), 1);
      overviews = n.state.deck!.slides
          .where((s) => s.type == SlideType.table && s.title == 'Voortgang')
          .toList();
      expect(overviews, hasLength(1));
    });

    test('returns 0 when there is nothing to summarise', () {
      final n = _notifier()
        ..loadDeck(Deck(title: 'D', slides: [Slide.create(SlideType.title)]));
      expect(gen(n), 0);
    });
  });

  group('buildManagementSystemProgressChart', () {
    test('a horizontal burn-up bar per section: implemented + remaining', () {
      final progress = deckManagementSystemProgress(
        Deck(
          title: 'D',
          slides: [
            _controlSlide('A.5', const [
              ControlStatus.implemented,
              ControlStatus.implemented,
              ControlStatus.notStarted,
              ControlStatus.notApplicable, // out of the applicable base
            ]),
            _controlSlide('A.6', const [ControlStatus.implemented]),
          ],
        ),
      );
      final spec = buildManagementSystemProgressChart(
        progress,
        chartTitle: 'Voortgang',
        implementedLabel: 'Geïmplementeerd',
        remainingLabel: 'Nog te doen',
      );
      expect(spec.type, ChartType.horizontalStackedBar);
      expect(spec.title, 'Voortgang');
      expect(spec.x, ['A.5', 'A.6']);
      expect(spec.series, hasLength(2));
      // A.5: 2 implemented, 3 applicable → 1 remaining. A.6: 1 and 0.
      expect(spec.series[0].data, [2, 1]);
      expect(spec.series[1].data, [1, 0]);
      // Done/todo meaning is carried by explicit colours, not the palette.
      expect(spec.series[0].color, isNotNull);
      expect(spec.series[1].color, isNotNull);
    });

    test('empty progress → empty spec (nothing to plot)', () {
      expect(
        buildManagementSystemProgressChart(
          const ManagementSystemProgress([]),
          chartTitle: 't',
          implementedLabel: 'i',
          remainingLabel: 'r',
        ).series,
        isEmpty,
      );
    });
  });

  group('generateManagementSystemChart', () {
    int gen(DeckNotifier n) => generateManagementSystemChart(
      n,
      chartTitle: 'Voortgang per sectie',
      implementedLabel: 'Geïmplementeerd',
      remainingLabel: 'Nog te doen',
    );

    test('adds a burn-up chart slide and refreshes it in place', () {
      final n = _notifier()
        ..loadDeck(
          Deck(
            title: 'D',
            slides: [
              _controlSlide('A.5', const [ControlStatus.implemented]),
            ],
          ),
        );
      expect(gen(n), 1);
      var charts = n.state.deck!.slides
          .where(
            (s) =>
                s.type == SlideType.chart &&
                ChartSpec.parse(s.customMarkdown).title ==
                    'Voortgang per sectie',
          )
          .toList();
      expect(charts, hasLength(1));
      // Idempotent: identified by the chart's own spec title, refreshed in place.
      expect(gen(n), 1);
      charts = n.state.deck!.slides
          .where(
            (s) =>
                s.type == SlideType.chart &&
                ChartSpec.parse(s.customMarkdown).title ==
                    'Voortgang per sectie',
          )
          .toList();
      expect(charts, hasLength(1));
    });
  });

  group('generateManagementReview', () {
    int gen(DeckNotifier n) => generateManagementReview(
      n,
      inputTitle: 'Review — Input',
      inputBody: 'Voortgang: {p}% ({impl}/{app})',
      outputTitle: 'Review — Output',
      outputBody: 'Besluiten',
    );

    test('appends two freeMarkdown slides, filled with the progress', () {
      final n = _notifier()
        ..loadDeck(
          Deck(
            title: 'D',
            slides: [
              _controlSlide('A.5', const [
                ControlStatus.implemented,
                ControlStatus.notStarted,
              ]),
            ],
          ),
        );
      expect(gen(n), 2);
      final free = n.state.deck!.slides
          .where((s) => s.type == SlideType.freeMarkdown)
          .toList();
      expect(free, hasLength(2));
      // Marker on the first, and the placeholders are filled from the deck.
      expect(free.first.customMarkdown, contains(kManagementReviewMarker));
      expect(free.first.customMarkdown, contains('Voortgang: 50% (1/2)'));
    });

    test('refuses to duplicate — the marker guard protects the answers', () {
      final n = _notifier()
        ..loadDeck(
          Deck(
            title: 'D',
            slides: [
              _controlSlide('A.5', const [ControlStatus.implemented]),
            ],
          ),
        );
      expect(gen(n), 2);
      expect(gen(n), 0);
      expect(
        n.state.deck!.slides
            .where((s) => s.type == SlideType.freeMarkdown)
            .length,
        2,
      );
    });
  });
}
