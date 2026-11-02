import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/utils/text_search.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/deck_text_search.dart';

void main() {
  List<DeckTextMatch> search(Slide slide, String query, {bool notes = false}) =>
      searchDeckText(
        Deck(title: '', slides: [slide]),
        query,
        includeNotes: notes,
      );

  test('each occurrence identifies a concrete field and stable slide', () {
    final slide = Slide.create(SlideType.twoBullets).copyWith(
      title: 'anker',
      columnTitle2: 'anker',
      bullets2: ['anker anker'],
      imagePath: '/private/anker.png',
      notes: 'anker',
    );
    final hits = search(slide, 'anker');
    expect(hits.map((h) => h.fieldId), [
      'title',
      'columnTitle2',
      'bullets2.0',
      'bullets2.0',
    ]);
    expect(hits.map((h) => h.range.start), [0, 0, 0, 6]);
    expect(hits.every((h) => h.slideId == slide.id), isTrue);
    expect(hits.map((h) => h.identity).toSet(), hasLength(4));
    expect(search(slide, 'anker', notes: true).last.isNotes, isTrue);
  });

  test('timeline matches parsed fields rather than storage separators', () {
    final slide = Slide.create(
      SlideType.timeline,
    ).copyWith(bullets: ['2026 :: Start :: De eerste fase']);
    expect(search(slide, 'Start').single.fieldId, 'timeline.0.title');
    expect(search(slide, 'fase').single.fieldId, 'timeline.0.description');
    expect(search(slide, '::'), isEmpty);
  });

  test('menu exposes labels and descriptions but never navigation targets', () {
    final slide = Slide.create(SlideType.menu).copyWith(
      bullets: [
        groupHeadingBullet('Onderwerpen'),
        '[Privacy](#interne-doeldia) — Praktische uitleg ![](geheim.png)',
      ],
    );
    expect(search(slide, 'Privacy').single.fieldId, 'menu.0.label');
    expect(search(slide, 'uitleg').single.fieldId, 'menu.0.description');
    expect(search(slide, 'Onderwerpen').single.fieldId, 'menuCategory.0');
    expect(search(slide, 'interne-doeldia'), isEmpty);
    expect(search(slide, 'geheim'), isEmpty);
  });

  test(
    'visible labels match across markup, literal code keeps punctuation',
    () {
      final markdown = Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(customMarkdown: 'een **belangrijke** [passage](doel.md)');
      final hit = search(markdown, 'belangrijke passage').single;
      expect(hit.context, contains('belangrijke passage'));
      expect(search(markdown, 'doel.md'), isEmpty);
      final code = Slide.create(
        SlideType.code,
      ).copyWith(customMarkdown: 'const String raw = "**letterlijk**";');
      expect(
        search(code, '**letterlijk**').single.context,
        contains('**letterlijk**'),
      );
    },
  );

  test(
    'structured table schema and unrelated retained fields are not hits',
    () {
      final slide = Slide.create(SlideType.scorecard).copyWith(
        subtitle: 'onzichtbare oude subtitel',
        bullets: ['onzichtbare oude bullet'],
        tableRows: [
          ['Label', 'Value', 'Previous', 'Unit', 'Polarity'],
          ['Dekking', '80', '70', '%', 'higherBetter'],
        ],
      );
      expect(search(slide, 'Dekking').single.fieldId, 'tableRows.1.0');
      expect(search(slide, 'Label'), isEmpty);
      expect(search(slide, 'higherBetter'), isEmpty);
      expect(search(slide, 'onzichtbare'), isEmpty);
    },
  );

  test('questions expose hints and feedback but not hidden answer keys', () {
    final question = QuestionSpec(
      kind: QuestionKind.openText,
      prompt: 'Wat is de term?',
      answers: const [QuestionAnswer(text: 'geheime sleutel', correct: true)],
      hints: const ['Een herkenbare aanwijzing'],
      feedback: const QuestionFeedback(correct: 'Dat is een prima uitleg'),
    );
    final slide = Slide.create(
      SlideType.question,
    ).copyWith(customMarkdown: question.toBlock());
    expect(search(slide, 'aanwijzing').single.fieldId, 'question.hints');
    expect(search(slide, 'prima').single.fieldId, 'question.feedback.correct');
    expect(search(slide, 'geheime sleutel'), isEmpty);
    expect(search(slide, 'maxAttempts'), isEmpty);
  });
  test('canvas and finding use the same typed fields as their editors', () {
    final canvas = Slide.create(SlideType.canvas).copyWith(
      improvementTemplateId: 'unknown',
      customMarkdown: '## Kansen\n\nEen **vindbare** passage.\n',
    );
    expect(search(canvas, 'vindbare').single.fieldId, 'canvas.kansen.body');
    final finding = Slide.create(SlideType.finding).copyWith(
      title: 'verborgen-restveld',
      customMarkdown: const FindingSpec(
        heading: 'Zichtbare kop',
        scopeObject: 'app.example.invalid',
        cvssVector:
            'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N',
        cweId: 89,
        cweName: 'SQL Injection',
        cveIds: ['CVE-2026-12345'],
        description: 'Een beschrijving',
        confirmation: 'Bewijs',
        impact: 'Gevolg',
        recommendation: 'Een advies',
        testId: 'WSTG-TEST',
        masweId: 'MASWE-0001',
      ).toMarkdown(),
    );
    expect(search(finding, 'verborgen-restveld'), isEmpty);
    expect(search(finding, 'Zichtbare kop').single.fieldId, 'finding.heading');
    expect(
      search(finding, 'SQL Injection').single.text,
      'CWE-89 — SQL Injection',
    );
    expect(search(finding, 'advies').single.fieldId, 'finding.recommendation');
    expect(search(finding, 'WSTG-TEST').single.fieldId, 'finding.testId');
  });

  test(
    'chart and cockpit expose labels without leaking JSON or source paths',
    () {
      final chart = Slide.create(SlideType.chart).copyWith(
        customMarkdown: const ChartSpec(
          title: 'Jaaroverzicht',
          x: ['Maart'],
          series: [
            ChartSeries(name: 'Groei', data: [4]),
          ],
          source: 'data/verborgen.json',
        ).toBlock(),
      );
      expect(search(chart, 'Jaaroverzicht').single.fieldId, 'chart.title');
      expect(search(chart, 'Maart').single.fieldId, 'chart.x.0');
      expect(search(chart, 'Groei').single.fieldId, 'chart.series.0');
      expect(search(chart, 'verborgen'), isEmpty);
      final cockpit = Slide.create(SlideType.cockpit).copyWith(
        customMarkdown: const CockpitSpec(
          meters: [
            CockpitMeterSpec(
              type: CockpitMeterType.heading,
              label: 'Bereik',
              unit: 'procent',
              markerLabel: 'Streefwaarde',
            ),
          ],
        ).toBlock(),
      );
      expect(search(cockpit, 'Bereik').single.fieldId, 'cockpit.0.label');
      expect(search(cockpit, 'procent').single.fieldId, 'cockpit.0.unit');
      expect(
        search(cockpit, 'Streefwaarde').single.fieldId,
        'cockpit.0.markerLabel',
      );
    },
  );

  test('flow hides kind and attributes in both hits and context', () {
    final slide = Slide.create(
      SlideType.flow,
    ).copyWith(bullets: ['Werk voorbereiden :: process :: pt=3m; lane = Team']);
    expect(search(slide, 'process'), isEmpty);
    expect(search(slide, 'pt='), isEmpty);
    final title = search(slide, 'voorbereiden').single;
    expect(title.context, 'Werk voorbereiden · Team');
    expect(search(slide, 'Team').single.fieldId, 'bullets.0');
  });

  test(
    'notes point to the right page and reordering preserves hit identity',
    () {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(notes: '<!-- ocideck_page:2 -->\nTweede notitiepagina');
      expect(search(slide, 'notitiepagina'), isEmpty);
      final first = search(slide, 'notitiepagina', notes: true).single;
      expect(first.fieldId, 'notes.1');
      final other = Slide.create(SlideType.title);
      final moved = searchDeckText(
        Deck(title: '', slides: [other, slide]),
        'notitiepagina',
        includeNotes: true,
      ).single;
      expect(moved.identity, first.identity);
      expect(moved.slideIndex, 1);
      expect(search(slide, ''), isEmpty);
      expect(search(slide, 'TWEEDE', notes: true), hasLength(1));
      expect(
        searchDeckText(
          Deck(title: '', slides: [slide]),
          'TWEEDE',
          includeNotes: true,
          caseSensitive: true,
        ),
        isEmpty,
      );
    },
  );

  test('every slide type enumerates only its content without changing it', () {
    for (final type in SlideType.values) {
      final slide = Slide.create(type);
      final before = [
        slide.title,
        slide.customMarkdown,
        slide.notes,
        [...slide.bullets],
        [...slide.bullets2],
        [
          for (final row in slide.tableRows) [...row],
        ],
      ];
      final fields = slideTextFields(slide, includeNotes: true).toList();
      expect(
        fields.map((f) => f.id).toSet(),
        hasLength(fields.length),
        reason: '$type',
      );
      for (final field in fields.where((f) => f.text.isNotEmpty)) {
        search(slide, field.text.substring(0, 1), notes: true);
      }
      expect(
        [
          slide.title,
          slide.customMarkdown,
          slide.notes,
          slide.bullets,
          slide.bullets2,
          slide.tableRows,
        ],
        before,
        reason: '$type',
      );
    }
  });

  test('600-slide and 300-page corpora yield concrete complete results', () {
    final deck = Deck(
      title: '',
      slides: List.generate(
        600,
        (i) => Slide.create(SlideType.bullets).copyWith(
          title: 'Hoofdstuk $i',
          bullets: ['Een **zichtbare** passage en nog een passage.'],
        ),
      ),
    );
    final watch = Stopwatch()..start();
    final hits = searchDeckText(deck, 'passage');
    watch.stop();
    expect(hits, hasLength(1200));
    expect(hits.last.slideIndex, 599);
    expect(watch.elapsedMilliseconds, lessThan(1500));
    final source = List.generate(
      300,
      (i) =>
          '# Hoofdstuk $i\n\n${'Een alinea met **opmaak** en tekst. ' * 20}\n\nSlotmarkering.',
    ).join('\n\n');
    final visible = VisibleMarkdownText(source);
    final matches = findVisibleMarkdownMatches(source, 'Slotmarkering');
    expect(matches, hasLength(300));
    expect(visible.context(matches.last), contains('Slotmarkering'));
  });
  test('rich text does not search retained old bullets', () {
    final slide = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.richText,
      customMarkdown: 'De actuele passage',
      bullets: ['oude verborgen passage'],
    );
    expect(search(slide, 'passage').single.fieldId, 'customMarkdown');
    expect(search(slide, 'oude verborgen'), isEmpty);
  });
  test(
    'question kinds search their visible fields and keep accepted keys hidden',
    () {
      final cases = <(QuestionSpec, List<String>)>[
        (
          const QuestionSpec(
            kind: QuestionKind.matching,
            pairs: [MatchPair(left: 'vind links', right: 'vind rechts')],
            distractors: ['vind afleider'],
          ),
          [
            'question.pairs.0.left',
            'question.pairs.0.right',
            'question.distractors.0',
          ],
        ),
        (
          const QuestionSpec(
            kind: QuestionKind.hotspot,
            regions: [HotspotRegion(label: 'vind gebied')],
          ),
          ['question.regions.0'],
        ),
        (
          const QuestionSpec(
            kind: QuestionKind.fillIn,
            fields: [
              FillField(
                placeholder: 'vind invoer',
                unit: 'vind eenheid',
                accepted: ['verborgen sleutel'],
              ),
            ],
          ),
          ['question.fields.0', 'question.fields.0.unit'],
        ),
        (
          const QuestionSpec(answers: [QuestionAnswer(text: 'vind antwoord')]),
          ['question.answers.0'],
        ),
      ];
      for (final (spec, expected) in cases) {
        final slide = Slide.create(
          SlideType.question,
        ).copyWith(customMarkdown: spec.toBlock());
        expect(search(slide, 'vind').map((hit) => hit.fieldId), expected);
        expect(search(slide, 'verborgen sleutel'), isEmpty);
      }
    },
  );

  test(
    'Gantt task names do not expose storage status or milestone prefixes',
    () {
      final slide = Slide.create(SlideType.gantt).copyWith(
        tableRows: [
          ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van'],
          ['Milestone: Oplevering', '2026-11-03', '1d', 'crit', ''],
        ],
      );
      expect(search(slide, 'Oplevering').single.context, 'Oplevering');
      expect(search(slide, 'Milestone'), isEmpty);
      expect(search(slide, 'crit'), isEmpty);
      expect(search(slide, 'Afhankelijk van'), isEmpty);
    },
  );
}
