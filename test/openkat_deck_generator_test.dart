import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
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
  bool comparable = true,
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: 'rapport-${date.year}${date.month}${date.day}.json',
  sourceHash: 'hash-${date.year}${date.month}${date.day}',
  systems: systems,
  findings: findings,
  controls: controls,
  sourceFeatures: comparable
      ? const {OpenKatSourceFeature.comparableMeasurementCoverage}
      : const {},
  measurementScopeId: comparable ? 'fixture-scope' : null,
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

  test('de headless rapportagemotor is via de publieke façade bereikbaar', () {
    expect(OpenKatReportEngine(), isA<OpenKatReportEngine>());
  });

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

    test(
      'zonder broncapability verschijnt alleen een vergelijkingswaarschuwing',
      () {
        final org = _orgMetVerloop('a');
        final deck = generator.generate([
          org.copyWith(
            snapshots: [
              for (final snapshot in org.snapshots)
                snapshot.copyWith(
                  sourceFeatures: const {},
                  clearMeasurementScopeId: true,
                ),
            ],
          ),
        ]);

        expect(_hasView(deck, 'portfolio.comparison-warning'), isTrue);
        expect(_hasView(deck, 'portfolio.key-message'), isFalse);
        expect(_hasView(deck, 'org.a.improved'), isFalse);
        final scorecard = ScorecardSpec.fromSlide(
          _view(deck, 'portfolio.summary').title,
          _view(deck, 'portfolio.summary').tableRows,
        );
        expect(
          scorecard.entries.every((entry) => entry.previous == null),
          isTrue,
        );
      },
    );
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

  group('wat OpenKAT aanraadt', () {
    test('de aanbeveling komt onder een tussenkop te staan', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.recommendations');

      expect(slide.bullets.first, startsWith(kGroupHeadingMarker));
      expect(isGroupHeading(slide.bullets.first), isTrue);
      expect(slide.bullets, contains('Zet de header aan.'));
    });

    test('de tussenkop overleeft de gang door het bestand', () {
      // De tussenkop is een teken in de tekst van de bullet, geen eigen veld.
      // Als het schrijven of lezen hem kwijtraakt, ziet niemand dat: de dia
      // toont dan een lijst waarin advies en finding door elkaar lopen.
      final deck = generator.generate([_orgMetVerloop('a')]);
      final heen = MarkdownService().generateDeck(deck);
      final terug = MarkdownService().parseDeck(heen)!;
      final slide = _view(terug, 'portfolio.recommendations');

      expect(isGroupHeading(slide.bullets.first), isTrue);
      expect(groupHeadingText(slide.bullets.first), 'Type KAT-001');
      expect(slide.bullets[1], 'Zet de header aan.');
    });

    test('zonder aanbevelingen is er geen dia', () {
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
      expect(_hasView(deck, 'portfolio.recommendations'), isFalse);
    });
  });

  group('dekking per control', () {
    test('het percentage komt uit de teller en de noemer', () {
      final deck = generator.generate([
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'f1', severity: 'high')],
              controls: const {
                'rpki': OpenKatControlScore(
                  name: 'rpki',
                  compliant: 1,
                  total: 2,
                ),
              },
            ),
          ],
        ),
      ]);
      final chart = ChartSpec.parse(
        _view(deck, 'portfolio.controls').customMarkdown,
      );

      expect(chart.type, ChartType.horizontalBar);
      expect(chart.x, ['rpki']);
      expect(chart.series.first.data, [50]);
      expect(
        chart.bands,
        isEmpty,
        reason: 'welk percentage goed genoeg is staat niet in de meting',
      );
    });

    test('zonder dekkingscijfers is er geen dia', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      expect(_hasView(deck, 'portfolio.controls'), isFalse);
    });
  });

  group('de tabellen zeggen wat ze tonen', () {
    test('langst openstaand telt de dagen tegen de rapportagedatum', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.longest-open');

      expect(slide.tableRows.first, [
        '#',
        'Systeem',
        'Finding',
        'Ernst',
        'Open sinds',
        'Dagen',
      ]);
      // Geopend 1 april, gemeten 1 juni: 61 dagen — en dat blijft 61, ook als
      // dit deck over een half jaar opnieuw wordt geopend.
      expect(slide.tableRows[1].last, '61');
      expect(slide.tableRows[1][4], '2026-04-01');
    });

    test('de kolom "nieuw" verschijnt alleen met een vorige meting', () {
      final metVorige = generator.generate([_orgMetVerloop('a')]);
      expect(
        _view(metVorige, 'portfolio.top-issues').tableRows.first,
        contains('Nieuw'),
      );

      final eersteMeting = generator.generate([
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
      expect(
        _view(eersteMeting, 'portfolio.top-issues').tableRows.first,
        isNot(contains('Nieuw')),
      );
    });

    test('de titel noemt geen aantal dat de limiet tegenspreekt', () {
      final deck = generator.generate([_orgMetVerloop('a')]);
      final slide = _view(deck, 'portfolio.top-issues');
      expect(slide.title, isNot(contains('5')));
      expect(slide.viewLimit?.limit, 5);
    });
  });

  group('de herimport vindt de gegenereerde dia terug', () {
    test('de origin-marker overleeft opslaan maar niet dupliceren', () {
      final eerste = generator.generate([_orgMetVerloop('a')]);
      final terug = MarkdownService().parseDeck(
        MarkdownService().generateDeck(eerste),
      )!;
      final origineel = _view(terug, 'portfolio.summary');
      final kopie = Slide.duplicate(origineel);

      expect(origineel.notes, contains(openKatGeneratedOriginMarker));
      expect(kopie.notes, isNot(contains(openKatGeneratedOriginMarker)));
      expect(kopie.notes, contains('ocideck_openkat_view: portfolio.summary'));
    });

    test('een vervangen dia houdt zijn plek en zijn id', () {
      final eerste = generator.generate([_orgMetVerloop('a')]);
      final tweede = generator.update(eerste, [_orgMetVerloop('a')]);

      expect(
        tweede.slides.map((s) => s.id),
        eerste.slides.map((s) => s.id),
        reason: 'zelfde invoer, zelfde dia-ids — anders schuift een herimport',
      );
    });

    test(
      'een verplaatste handmatige kopie blijft naast het origineel staan',
      () {
        final eerste = generator.generate([_orgMetVerloop('a')]);
        final origineel = _view(eerste, 'portfolio.summary');
        final kopie = Slide.duplicate(
          origineel,
        ).copyWith(title: 'Mijn handmatige kopie');
        final zonderOrigineel = eerste.slides
            .where((slide) => slide.id != origineel.id)
            .toList();
        final bestaand = eerste.copyWith(
          slides: [kopie, ...zonderOrigineel, origineel],
        );
        final vers = generator.generate([_orgMetVerloop('a')]);

        final bijgewerkt = generator.updateGenerated(bestaand, vers);

        expect(
          bijgewerkt.slides.where((slide) => slide.id == kopie.id).single.title,
          'Mijn handmatige kopie',
        );
        expect(
          bijgewerkt.slides.where((slide) => slide.id == origineel.id),
          hasLength(1),
          reason: 'alleen het deterministische origineel wordt vervangen',
        );
        expect(kopie.notes, isNot(contains(openKatGeneratedOriginMarker)));
      },
    );

    test('de originele dia houdt haar privacykeuze bij vervanging', () {
      final eerste = generator.generate([_orgMetVerloop('a')]);
      final origineel = _view(eerste, 'portfolio.summary');
      final bestaand = eerste.copyWith(
        slides: [
          for (final slide in eerste.slides)
            slide.id == origineel.id
                ? slide.copyWith(privacy: PrivacyDisposition.redact)
                : slide,
        ],
      );

      final bijgewerkt = generator.updateGenerated(
        bestaand,
        generator.generate([_orgMetVerloop('a')]),
      );

      expect(
        _view(bijgewerkt, 'portfolio.summary').privacy,
        PrivacyDisposition.redact,
      );
    });

    test(
      'scopeverkleining verwijdert vervallen en optionele views maar geen kopie',
      () {
        final eerste = generator.generate([
          _orgMetVerloop('a'),
          _orgMetVerloop('b'),
        ]);
        final origineel = _view(eerste, 'org.b.summary');
        final kopie = Slide.duplicate(
          origineel,
        ).copyWith(title: 'Mijn bewaarde analyse');
        final bestaand = eerste.copyWith(slides: [...eerste.slides, kopie]);
        final vers = generator.generate([_orgMetVerloop('a')]);

        final bijgewerkt = generator.updateGenerated(bestaand, vers);

        expect(
          bijgewerkt.slides.where((slide) => slide.id == origineel.id),
          isEmpty,
          reason: 'een niet meer gebouwde gegenereerde view is verouderd',
        );
        expect(
          bijgewerkt.slides.where((slide) => slide.id == kopie.id).single.title,
          'Mijn bewaarde analyse',
        );
        expect(
          _hasView(bijgewerkt, 'portfolio.orgs-compared'),
          isFalse,
          reason: 'de optionele vergelijkingsview bestaat niet meer in vers',
        );
      },
    );

    test('een ambigu legacy-origineel stopt de update fail-closed', () {
      final eerste = generator.generate([_orgMetVerloop('a')]);
      final origineel = _view(eerste, 'org.a.summary');
      final legacyEen = Slide.duplicate(origineel);
      final legacyTwee = Slide.duplicate(origineel);
      final bestaand = eerste.copyWith(
        slides: [
          for (final slide in eerste.slides)
            if (slide.id != origineel.id) slide,
          legacyEen,
          legacyTwee,
        ],
      );
      final vers = eerste.copyWith(
        slides: [
          for (final slide in eerste.slides)
            if (slide.id != origineel.id) slide,
        ],
      );

      expect(
        () => generator.updateGenerated(bestaand, vers),
        throwsA(
          isA<OpenKatUnsafeUpdateException>().having(
            (error) => error.viewId,
            'viewId',
            'org.a.summary',
          ),
        ),
      );
    });

    test(
      'een enige aangepaste kopie wordt niet voor het origineel aangezien',
      () {
        final eerste = generator.generate([_orgMetVerloop('a')]);
        final origineel = _view(eerste, 'org.a.summary');
        final kopie = Slide.duplicate(
          origineel,
        ).copyWith(title: 'Mijn enige aangepaste analyse');
        final bestaand = eerste.copyWith(
          slides: [
            for (final slide in eerste.slides)
              if (slide.id != origineel.id) slide,
            kopie,
          ],
        );

        expect(
          () => generator.updateGenerated(
            bestaand,
            generator.generate([_orgMetVerloop('a')]),
          ),
          throwsA(isA<OpenKatUnsafeUpdateException>()),
        );
        expect(kopie.title, 'Mijn enige aangepaste analyse');
      },
    );

    test(
      'een enige aangepaste kopie van een vervallen view blijft fail-closed',
      () {
        final eerste = generator.generate([
          _orgMetVerloop('a'),
          _orgMetVerloop('b'),
        ]);
        final origineel = _view(eerste, 'org.b.summary');
        final kopie = Slide.duplicate(
          origineel,
        ).copyWith(title: 'Mijn bewaarde analyse');
        final bestaand = eerste.copyWith(
          slides: [
            for (final slide in eerste.slides)
              if (slide.id != origineel.id) slide,
            kopie,
          ],
        );

        expect(
          () => generator.updateGenerated(
            bestaand,
            generator.generate([_orgMetVerloop('a')]),
          ),
          throwsA(isA<OpenKatUnsafeUpdateException>()),
        );
        expect(kopie.title, 'Mijn bewaarde analyse');
      },
    );

    test(
      'een extern gekopieerde en bewerkte Markdown-dia stopt fail-closed',
      () {
        final eerste = generator.generate([_orgMetVerloop('a')]);
        final origineel = _view(eerste, 'org.a.summary');
        final bron = MarkdownService().generateDeck(
          eerste.copyWith(slides: [origineel]),
        );
        // Een volledige diablock kopiëren, het origineel verwijderen en daarna
        // de kop bewerken laat op schijf precies dit ene bewerkte block over,
        // inclusief de meegereisde provenancecomment.
        final externBewerkt = bron.replaceFirst(
          origineel.title,
          'Mijn externe analyse',
        );
        final heropend = MarkdownService().parseDeck(externBewerkt)!;

        expect(
          () => generator.updateGenerated(
            heropend,
            generator.generate([_orgMetVerloop('a')]),
          ),
          throwsA(isA<OpenKatUnsafeUpdateException>()),
        );
        expect(_view(heropend, 'org.a.summary').title, 'Mijn externe analyse');
      },
    );

    test('een scenariowissel laat geen views van het oude scenario staan', () {
      final organization = _orgMetVerloop('a');
      final bestaand = generator.generate([organization]);
      final vers = OpenKatReportEngine().generate(
        [organization],
        OpenKatReportRequest(
          scenarioId: 'data-quality',
          scope: const OpenKatReportScope.portfolio(),
          currentAsOf: DateTime.utc(2026, 6, 1),
        ),
      ).deck!;

      final bijgewerkt = generator.updateGenerated(bestaand, vers);

      expect(_hasView(bijgewerkt, 'portfolio.summary'), isFalse);
      expect(_hasView(bijgewerkt, 'report.data-quality.availability'), isTrue);
    });

    test('titel en rapporttaal komen uit het verse scenariodeck', () {
      final bestaand = generator
          .generate([_orgMetVerloop('a')])
          .copyWith(title: 'Oude titel', language: 'nl');
      final vers = generator
          .generate([_orgMetVerloop('a')])
          .copyWith(title: 'Fresh title', language: 'en');

      final bijgewerkt = generator.updateGenerated(bestaand, vers);

      expect(bijgewerkt.title, 'Fresh title');
      expect(bijgewerkt.language, 'en');
    });
  });
}
