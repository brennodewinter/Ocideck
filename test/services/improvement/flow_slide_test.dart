import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/improvement/flow_layout.dart';
import 'package:ocideck/services/improvement/flow_slide.dart';
import 'package:ocideck/services/improvement/flow_spec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/scene/scene.dart';

void main() {
  group('flow slide', () {
    test('fresh flow starts as process-map with starter bullets', () {
      final slide = Slide.create(SlideType.flow);
      expect(slide.improvementTemplateId, kDefaultFlowTemplateId);
      expect(slide.improvementLayout, 'flow');
      expect(slide.bullets, flowStarterBullets(kDefaultFlowTemplateId));
    });

    test('parseDurationMinutes accepts m, h and d suffixes', () {
      expect(parseDurationMinutes('12m'), 12);
      expect(parseDurationMinutes('2h'), 120);
      expect(parseDurationMinutes('1d'), 24 * 60);
      expect(parseDurationMinutes('30'), 30);
    });

    test('parseFlowBullet reads title, kind and attrs', () {
      final step = parseFlowBullet(
        'Pick & pack :: process :: pt=35m; lt=3d; fte=4; fpy=0.88',
      );
      expect(step.title, 'Pick & pack');
      expect(step.kind, 'process');
      expect(step.processMinutes, 35);
      expect(step.leadMinutes, 3 * 24 * 60);
      expect(step.fte, 4);
      expect(step.fpy, closeTo(0.88, 0.001));
    });

    test('deriveFlowRollup computes PCE and bottleneck', () {
      final steps = [
        const FlowStep(
          title: 'A',
          kind: 'process',
          processMinutes: 10,
          leadMinutes: 100,
        ),
        const FlowStep(
          title: 'B',
          kind: 'process',
          processMinutes: 30,
          leadMinutes: 200,
        ),
      ];
      final rollup = deriveFlowRollup(steps);
      expect(rollup.totalProcessMinutes, 40);
      expect(rollup.totalLeadMinutes, 300);
      expect(rollup.pce, closeTo(40 / 300, 0.001));
      expect(rollup.bottleneckTitle, 'B');
    });

    test('Markdown round-trip keeps template, layout and bullets', () {
      final original = Slide.create(SlideType.flow).copyWith(
        title: 'Order flow',
        improvementTemplateId: 'vsm',
        improvementLayout: 'vsm',
        bullets: [
          'Enter order :: process :: pt=12m; lt=2d',
          ':: inventory :: wip=45',
        ],
      );
      final md = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [original]),
      );
      expect(md, contains('ocideck_template: vsm'));
      expect(md, contains('ocideck_layout: vsm'));
      final parsed = MarkdownService().parseDeck(md)!.slides.single;
      expect(parsed.type, SlideType.flow);
      expect(parsed.title, 'Order flow');
      expect(parsed.improvementTemplateId, 'vsm');
      expect(parsed.improvementLayout, 'vsm');
      expect(parsed.bullets, original.bullets);
    });

    test('VSM scene includes derived PCE text', () {
      final scene = buildFlowScene(
        steps: flowStepsFromBullets([
          'Step A :: process :: pt=10m; lt=1h',
          'Step B :: process :: pt=20m; lt=2h',
        ]),
        layout: FlowLayout.vsm,
        measurer: const ApproximateTextMeasurer(),
        title: 'Value stream',
      );
      final svg = sceneToSvg(scene);
      expect(svg, contains('<svg'));
      expect(svg, contains('PCE'));
      expect(svg, contains('Step A'));
    });

    test('HTML export replaces bullets with scene SVG', () {
      const md = '''
<!-- _class: flow -->
<!-- ocideck_template: process-map -->
<!-- ocideck_layout: flow -->
# Process

- Start :: process :: pt=5m; lt=5m
- Work :: process :: pt=10m; lt=1h
''';
      final out = renderFlowSlide(md);
      expect(out, contains('<svg'));
      expect(out, contains('Start'));
      expect(out, isNot(contains('- Start')));
    });
  });
}
