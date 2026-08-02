import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/improvement/chart_derivation.dart';
import 'package:ocideck/services/improvement/improvement_quality_bridge.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  group('improvement front matter', () {
    test('framework and Y-01 round-trip', () {
      final service = MarkdownService();
      final deck = Deck(
        title: 'Order intake',
        improvementFramework: 'dmaic',
        improvementY01Metric: const ImprovementY01Metric(
          name: 'Lead time in days',
        ),
        slides: [Slide.create(SlideType.title)],
      );
      final md = service.generateDeck(deck);
      expect(md, contains('ocideck_improvement_framework: dmaic'));
      expect(md, contains('ocideck_improvement_y01: Lead time in days'));

      final back = service.parseDeck(md)!;
      expect(back.improvementFramework, 'dmaic');
      expect(back.improvementY01, 'Lead time in days');
    });

    test('Y-01 name only does not invent usl keys', () {
      final service = MarkdownService();
      final deck = Deck(
        title: 'Order intake',
        improvementY01Metric: const ImprovementY01Metric(name: 'Lead time'),
        slides: [Slide.create(SlideType.title)],
      );
      final md = service.generateDeck(deck);
      expect(md, contains('ocideck_improvement_y01: Lead time'));
      expect(md, isNot(contains('ocideck_improvement_y01_usl')));
      expect(md, isNot(contains('ocideck_improvement_y01_lsl')));

      final back = service.parseDeck(md)!;
      expect(back.improvementY01Metric.name, 'Lead time');
      expect(back.improvementY01Metric.usl, isNull);
      expect(back.improvementY01Metric.lsl, isNull);
    });

    test('legacy markdown with only y01 name still opens', () {
      const md = '''
---
marp: true
theme: ocideck
title: Legacy
ocideck_improvement_y01: Doorlooptijd
---

<!-- _class: title -->

# Legacy
''';
      final deck = MarkdownService().parseDeck(md)!;
      expect(deck.improvementY01, 'Doorlooptijd');
      expect(deck.improvementY01Metric.usl, isNull);
    });

    test('chart JSON with local usl and no yRef keeps local limits', () {
      // CapabilityAnalysis verlangt ≥8 waarnemingen; minder weigert cpk.
      final spec = ChartSpec.parse('''
{"type":"histogram","usl":12,"lsl":2,"series":[{"name":"s","data":[3,4,5,6,7,8,9,10]}]}
''');
      expect(spec.yRef, isNull);
      expect(spec.usl, 12);
      expect(spec.lsl, 2);
      final view = deriveHistogram(spec);
      expect(view?.cpk, isNotNull);
    });

    test('empty improvement fields stay out of front matter', () {
      final md = MarkdownService().generateDeck(
        Deck(title: 'Leeg', slides: [Slide.create(SlideType.title)]),
      );
      expect(md, isNot(contains('ocideck_improvement_framework')));
      expect(md, isNot(contains('ocideck_improvement_y01')));
    });
  });

  group('golden-thread lint', () {
    test('orphan id when referenced outside tree only', () {
      final deck = Deck(
        title: 'T',
        slides: [
          Slide.create(SlideType.matrix).copyWith(
            title: 'FMEA',
            tableRows: [
              ['Mode', 'Effect'],
              ['Late delivery — **X-99**', ''],
            ],
          ),
        ],
      );
      final issues = improvementIssuesFrom(deck);
      expect(issues, hasLength(1));
      expect(issues.single.kind, SlideQualityIssueKind.improvementOrphanId);
      expect(issues.single.args['id'], 'X-99');
      expect(issues.single.severity, MarkdownValidationSeverity.warning);
    });

    test('unused id when only on tree', () {
      final deck = Deck(
        title: 'T',
        slides: [
          Slide.create(SlideType.tree).copyWith(
            title: 'CTQ',
            improvementTemplateId: 'ctq-tree',
            bullets: const ['Need — **Y-01**', '\tCTQ'],
          ),
        ],
      );
      final issues = improvementIssuesFrom(deck);
      expect(issues, hasLength(1));
      expect(issues.single.kind, SlideQualityIssueKind.improvementUnusedId);
      expect(issues.single.args['id'], 'Y-01');
    });

    test('no issue when id is defined on tree and referenced elsewhere', () {
      final deck = Deck(
        title: 'T',
        slides: [
          Slide.create(
            SlideType.tree,
          ).copyWith(bullets: const ['Need — **Y-01**']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: const ['Improve **Y-01**']),
        ],
      );
      expect(improvementIssuesFrom(deck), isEmpty);
    });
  });

  group('phaseGate meta', () {
    test('label, class and starter bullets', () {
      expect(SlideType.phaseGate.label, 'Fasepoort');
      expect(SlideType.phaseGate.marpClass, 'phase-gate');
      expect(SlideType.phaseGate.category, SlideCategory.procesverbetering);
      final slide = Slide.create(SlideType.phaseGate);
      expect(slide.bullets, hasLength(3));
      expect(slide.bullets.first, contains('Scope'));
    });

    test('serialises and parses via phase-gate class', () {
      final service = MarkdownService();
      final slide = Slide.create(
        SlideType.phaseGate,
      ).copyWith(title: 'Define gate');
      final md = service.generateDeck(Deck(title: 'P', slides: [slide]));
      final parsed = service.parseDeck(md)!.slides.single;
      expect(parsed.type, SlideType.phaseGate);
      expect(parsed.bullets, slide.bullets);
    });
  });
}
