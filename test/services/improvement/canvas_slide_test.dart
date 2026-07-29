import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/improvement/canvas_layout.dart';
import 'package:ocideck/services/improvement/canvas_slide.dart';
import 'package:ocideck/services/improvement/canvas_spec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/scene/scene.dart';

void main() {
  group('canvas slide', () {
    test('fresh canvas starts as A3 with English ## contract', () {
      final slide = Slide.create(SlideType.canvas);
      expect(slide.improvementTemplateId, kDefaultCanvasTemplateId);
      expect(slide.customMarkdown, contains('## Background'));
      expect(slide.customMarkdown, contains('## Follow-up'));
    });

    test('regions parse NL and EN headings against template', () {
      final regions = canvasRegionsFromMarkdown(
        '## Achtergrond\nKlachten.\n\n## Doel\n7 dagen.\n',
        templateId: 'a3',
      );
      expect(
        regions.firstWhere((r) => r.key == 'background').body,
        'Klachten.',
      );
      expect(regions.firstWhere((r) => r.key == 'goal').body, '7 dagen.');
    });

    test('Markdown round-trip keeps template and ## regions', () {
      final original = Slide.create(SlideType.canvas).copyWith(
        title: 'Lead time',
        improvementTemplateId: 'a3',
        customMarkdown:
            '## Background\nSlow.\n\n## Goal\nFaster.\n\n## Plan\nPilot.\n',
      );
      final md = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [original]),
      );
      expect(md, contains('_class: canvas'));
      expect(md, contains('ocideck_template: a3'));
      final parsed = MarkdownService().parseDeck(md)!.slides.single;
      expect(parsed.type, SlideType.canvas);
      expect(parsed.improvementTemplateId, 'a3');
      expect(parsed.title, 'Lead time');
      expect(parsed.customMarkdown, contains('## Background'));
      expect(parsed.customMarkdown, contains('Slow.'));
      expect(parsed.customMarkdown, isNot(contains('# Lead time')));
      // Second write must not duplicate the H1.
      final md2 = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [parsed]),
      );
      expect(
        RegExp(r'^# Lead time$', multiLine: true).allMatches(md2).length,
        1,
      );
    });

    test('template switch remaps by region key', () {
      final a3 = Slide.create(SlideType.canvas).copyWith(
        improvementTemplateId: 'a3',
        customMarkdown: '## Goal\nKeep this.\n',
      );
      final remapped = canvasMarkdownForTemplate(a3, 'charter');
      expect(remapped, contains('## Goal'));
      expect(remapped, contains('Keep this.'));
      expect(remapped, contains('## Problem'));
    });

    test('quadrant scene draws four boxes', () {
      final template = canvasTemplateById('swot')!;
      final regions = canvasRegionsFromMarkdown(
        canvasTemplateStarterMarkdown('swot'),
        templateId: 'swot',
      );
      final scene = buildCanvasScene(
        template: template,
        regions: regions,
        measurer: const ApproximateTextMeasurer(),
        title: 'SWOT',
      );
      expect(sceneToSvg(scene), contains('<svg'));
      expect(
        scene.nodes.whereType<SceneRect>().length,
        greaterThanOrEqualTo(4),
      );
    });

    test('HTML export replaces body with scene SVG', () {
      final md = '''
<!-- _class: canvas -->
<!-- ocideck_template: a3 -->
# A3 demo

## Background
Text here.

## Goal
Ship it.
''';
      final out = renderCanvasSlide(md);
      expect(out, contains('<svg'));
      expect(out, contains('_class: canvas'));
      expect(out, isNot(contains('## Background')));
    });
  });
}
