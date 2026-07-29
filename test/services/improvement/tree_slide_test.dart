import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/improvement/tree_layout.dart';
import 'package:ocideck/services/improvement/tree_slide.dart';
import 'package:ocideck/services/improvement/tree_spec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/scene/scene.dart';

void main() {
  group('tree slide', () {
    test('fresh tree starts as 5× Why with starter bullets', () {
      final slide = Slide.create(SlideType.tree);
      expect(slide.improvementTemplateId, kDefaultTreeTemplateId);
      expect(slide.improvementLayout, 'tree');
      expect(slide.bullets, treeStarterBullets(kDefaultTreeTemplateId));
    });

    test('improvementIdsInBullets and nextImprovementId', () {
      final bullets = [
        'Problem',
        '\tWhy — **X-01**',
        '\t\tRoot — **X-03**',
        '\tNeed — **Y-02**',
      ];
      expect(improvementIdsInBullets(bullets), ['X-01', 'X-03', 'Y-02']);
      expect(nextImprovementId('X', ['X-01', 'X-03']), 'X-04');
      expect(nextImprovementId('Y', ['Y-02']), 'Y-03');
    });

    test('Markdown round-trip keeps template, layout and tab depth', () {
      final original = Slide.create(SlideType.tree).copyWith(
        title: 'Root cause',
        improvementTemplateId: 'ishikawa',
        improvementLayout: 'fishbone',
        bullets: ['Man / People', '\tLate shift', 'Machine', '\tWorn belt'],
      );
      final md = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [original]),
      );
      expect(md, contains('ocideck_template: ishikawa'));
      expect(md, contains('ocideck_layout: fishbone'));
      final parsed = MarkdownService().parseDeck(md)!.slides.single;
      expect(parsed.type, SlideType.tree);
      expect(parsed.title, 'Root cause');
      expect(parsed.improvementTemplateId, 'ishikawa');
      expect(parsed.improvementLayout, 'fishbone');
      expect(parsed.bullets, original.bullets);
    });

    test('scene builds SVG for tree layout', () {
      final slide = Slide.create(SlideType.tree).copyWith(
        title: '5× Why',
        bullets: ['Problem', '\tWhy 1', '\t\tWhy 2 — **X-01**'],
      );
      final scene = buildTreeScene(
        bullets: slide.bullets,
        layout: TreeLayout.tree,
        measurer: const ApproximateTextMeasurer(),
        title: slide.title,
      );
      final svg = sceneToSvg(scene);
      expect(svg, contains('<svg'));
      expect(svg, contains('Problem'));
      expect(svg, contains('X-01'));
    });

    test('fishbone scene renders spine and categories', () {
      final scene = buildTreeScene(
        bullets: ['Method', '\tNo SOP', 'Machine', '\tCalibration drift'],
        layout: TreeLayout.fishbone,
        measurer: const ApproximateTextMeasurer(),
        title: 'Defect rate',
      );
      final svg = sceneToSvg(scene);
      expect(svg, contains('<svg'));
      expect(svg, contains('Effect'));
      expect(svg, contains('Method'));
    });

    test('HTML export replaces bullets with scene SVG', () {
      final md = '''
<!-- _class: tree -->
<!-- ocideck_template: five-whys -->
<!-- ocideck_layout: tree -->
# Why analysis

- Problem
\t- Why 1 — **X-01**
''';
      final out = renderTreeSlide(md);
      expect(out, contains('<svg'));
      expect(out, contains('Problem'));
      expect(out, isNot(contains('- Problem')));
    });
  });
}
