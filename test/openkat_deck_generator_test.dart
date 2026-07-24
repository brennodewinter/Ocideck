import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_deck_generator.dart';

OpenKatFinding _finding({
  required String id,
  required String severity,
  String system = 'example.com',
  String type = 'KAT-001',
  String? name,
  DateTime? openedAt,
  String? recommendation,
}) => OpenKatFinding(
  id: id,
  findingTypeId: type,
  findingTypeName: name ?? 'Type $type',
  severity: severity,
  systemId: system,
  openedAt: openedAt,
  recommendation: recommendation,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required List<OpenKatFinding> findings,
  List<OpenKatSystem> systems = const [],
  Map<String, OpenKatControlScore> controls = const {},
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: 'rapport-${date.year}${date.month}${date.day}.json',
  sourceHash: 'hash-${date.year}${date.month}${date.day}',
  systems: systems,
  findings: findings,
  controls: controls,
);

/// Eén organisatie met twee metingen, zodat elk verschil op de dia's te zien
/// is: eerst één high, daarna diezelfde high plus een medium erbij.
OpenKatOrganization _orgMetVerloop(String code) => OpenKatOrganization(
  code: code,
  name: code.toUpperCase(),
  snapshots: [
    _snapshot(
      date: DateTime.utc(2026, 5, 1),
      systems: const [
        OpenKatSystem(id: 'example.com', hostname: 'example.com'),
      ],
      findings: [_finding(id: '$code-1', severity: 'high')],
    ),
    _snapshot(
      date: DateTime.utc(2026, 6, 1),
      systems: const [
        OpenKatSystem(id: 'example.com', hostname: 'example.com'),
      ],
      findings: [
        _finding(id: '$code-1', severity: 'high'),
        _finding(
          id: '$code-2',
          severity: 'medium',
          openedAt: DateTime.utc(2026, 4, 1),
          recommendation: 'Zet de header aan.',
        ),
      ],
    ),
  ],
);

Slide _view(Deck deck, String view) => deck.slides.firstWhere(
  (s) => s.notes.contains('ocideck_openkat_view: $view'),
);

bool _hasView(Deck deck, String view) =>
    deck.slides.any((s) => s.notes.contains('ocideck_openkat_view: $view'));

void main() {
  const generator = OpenKatDeckGenerator();

  group('kerncijfers als scorecard', () {
    test('het portfolio toont elk getal naast wat het was', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.summary');

      expect(slide.type, SlideType.scorecard);
      final spec = ScorecardSpec.fromSlide(slide.title, slide.tableRows);
      final medium = spec.entries.firstWhere((e) => e.label == 'Medium');
      expect(medium.value, 1);
      expect(medium.previous, 0);
      expect(
        medium.sentiment,
        ScorecardSentiment.bad,
        reason: 'meer findings is slecht nieuws; de kleur moet dat zeggen',
      );
    });

    test('een eerste meting toont geen verzonnen verschil', () {
      final deck = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
            ),
          ],
        ),
      ]);
      final spec = ScorecardSpec.fromSlide(
        _view(deck, 'portfolio.summary').title,
        _view(deck, 'portfolio.summary').tableRows,
      );
      expect(spec.entries.every((e) => e.previous == null), isTrue);
      expect(spec.entries.every((e) => e.delta == null), isTrue);
    });

    test('de inventarisatie staat los van de cijfers die kleuren', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.surface');
      expect(slide.type, SlideType.bullets);
      expect(slide.bullets.any((b) => b.contains('systemen')), isTrue);
    });

    test('een organisatie krijgt dezelfde behandeling', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'org.a.summary');
      expect(slide.type, SlideType.scorecard);

      final spec = ScorecardSpec.fromSlide(slide.title, slide.tableRows);
      expect(spec.entries.length, scorecardMaxEntries);
      final systemen = spec.entries.firstWhere((e) => e.label == 'Systemen');
      expect(
        systemen.polarity,
        ScorecardPolarity.neutral,
        reason: 'meer systemen in beeld is geen slecht nieuws',
      );
    });
  });

  group('organisaties vergeleken', () {
    test('verschijnt zodra er meer dan één organisatie is', () {
      final een = generator.generate([_orgMetVerloop('a')]);
      final twee = generator.generate([
        _orgMetVerloop('a'),
        _orgMetVerloop('b'),
      ]);

      expect(_hasView(een, 'portfolio.orgs-compared'), isFalse);
      expect(_hasView(twee, 'portfolio.orgs-compared'), isTrue);
      expect(_view(twee, 'portfolio.orgs-compared').type, SlideType.scorecard);
    });

    test('meer dan vijf organisaties passen in de scorecard', () {
      // De scorecard houdt zichzelf op vijf regels; de warmtekaart is het
      // volledige beeld.
      final deck = generator.generate([
        for (var i = 0; i < 8; i++) _orgMetVerloop('org$i'),
      ]);
      final slide = _view(deck, 'portfolio.orgs-compared');
      final spec = ScorecardSpec.fromSlide(slide.title, slide.tableRows);
      expect(spec.entries.length, scorecardMaxEntries);
    });
  });

  group('het verloop over de tijd', () {
    test('meerdere metingen worden een lijn door de tijd', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.trend').customMarkdown,
      );

      expect(chart.type, ChartType.line);
      expect(chart.x, ['2026-05-01', '2026-06-01']);
      final medium = chart.series.firstWhere((s) => s.name == 'Medium');
      expect(medium.data, [0, 1]);
    });

    test('elke band houdt op elke dia dezelfde kleur', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.trend').customMarkdown,
      );
      final kleuren = {for (final s in chart.series) s.name: s.color};

      expect(kleuren['Critical'], isNotNull);
      expect(
        kleuren.values.toSet().length,
        kleuren.length,
        reason: 'twee banden in dezelfde kleur maakt de grafiek onleesbaar',
      );
    });

    test('één meting blijft een staafdiagram van de stand van nu', () {
      final deck = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
            ),
          ],
        ),
      ]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.trend').customMarkdown,
      );

      expect(
        chart.type,
        ChartType.bar,
        reason: 'een lijn van één punt is geen grafiek',
      );
      expect(chart.x, ['Critical', 'High', 'Medium', 'Low']);
    });

    test('de restband verschijnt alleen als er iets in valt', () {
      final zonder = ChartSpec.parse(
        _view(
          generator.generate([_orgMetVerloop('a')]),
          'portfolio.trend',
        ).customMarkdown,
      );
      expect(zonder.series.map((s) => s.name), isNot(contains('Overig')));

      final met = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 5, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
            ),
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f2', severity: 'recommendation')],
            ),
          ],
        ),
      ]);
      final chart = ChartSpec.parse(
        _view(met, 'portfolio.trend').customMarkdown,
      );
      expect(chart.series.map((s) => s.name), contains('Overig'));
    });

    test('een organisatie met meer metingen krijgt haar eigen verloop', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      expect(_hasView(deck, 'org.a.history'), isTrue);
      expect(
        ChartSpec.parse(_view(deck, 'org.a.history').customMarkdown).type,
        ChartType.line,
      );
    });

    test('een organisatie met één meting krijgt er geen', () {
      final deck = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
            ),
          ],
        ),
      ]);
      expect(_hasView(deck, 'org.a.history'), isFalse);
    });
  });

  group('wat het rapport zegt', () {
    test('de conclusiezinnen halen de dia', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.key-message');

      expect(slide.subtitle, contains('Slechter'));
      expect(slide.bullets, contains('1 meer medium findings'));
    });

    test('een eerste meting krijgt geen conclusie over verandering', () {
      final deck = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
            ),
          ],
        ),
      ]);
      expect(_hasView(deck, 'portfolio.key-message'), isFalse);
    });
  });

  group('ernst per organisatie', () {
    test('elke organisatie is een rij, elke band een kolom', () {
      final deck = generator.generate([
        _orgMetVerloop('a'),
        _orgMetVerloop('b'),
      ]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.severity-matrix').customMarkdown,
      );

      expect(chart.type, ChartType.heatmap);
      expect(chart.series.map((s) => s.name), ['A', 'B']);
      expect(chart.x, ['Critical', 'High', 'Medium', 'Low']);
      expect(chart.series.first.data, [0, 1, 1, 0]);
    });

    test('bij één organisatie blijft de warmtekaart weg', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      expect(_hasView(deck, 'portfolio.severity-matrix'), isFalse);
    });

    test('acht organisaties passen er alle acht in', () {
      // Waar de scorecard bij vijf ophoudt, moet dit doorschalen.
      final deck = generator.generate([
        for (var i = 0; i < 8; i++) _orgMetVerloop('org$i'),
      ]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.severity-matrix').customMarkdown,
      );
      expect(chart.series.length, 8);
    });
  });

  group('de herimport vindt de gegenereerde dia terug', () {
    test('een vervangen dia houdt zijn plek en zijn id', () {
      final eerste = generator.generate([_orgMetVerloop('a')]);
      final tweede = generator.update(eerste, [_orgMetVerloop('a')]);

      expect(
        tweede.slides.map((s) => s.id),
        eerste.slides.map((s) => s.id),
        reason: 'zelfde invoer, zelfde dia-ids — anders schuift een herimport',
      );
    });
  });
}
