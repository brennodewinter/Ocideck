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
      expect(svg, isNot(contains('**')));
      expect(svg, isNot(contains('•')));
    });

    test('a 5× Why chain fills the slide as a descending staircase', () {
      final scene = buildTreeScene(
        bullets: [
          'Order entered late',
          '\tApproval is awaited',
          '\t\tThe approval limit is unclear',
          '\t\t\tTwo policies contradict each other',
          '\t\t\t\tPolicy never merged after the merger',
          '\t\t\t\t\tNo owner was assigned — **X-03**',
        ],
        layout: TreeLayout.tree,
        measurer: const ApproximateTextMeasurer(),
        title: '5× Why',
        guidance: 'Five levels deep — end with an X-id.',
      );
      final cards = scene.nodes
          .whereType<SceneRect>()
          .where((rect) => rect.width > 80)
          .toList();
      expect(cards, hasLength(6));
      final top = cards.map((rect) => rect.y).reduce((a, b) => a < b ? a : b);
      final bottom = cards
          .map((rect) => rect.y + rect.height)
          .reduce((a, b) => a > b ? a : b);
      final left = cards.map((rect) => rect.x).reduce((a, b) => a < b ? a : b);
      final right = cards
          .map((rect) => rect.x + rect.width)
          .reduce((a, b) => a > b ? a : b);
      expect(bottom - top, greaterThan(scene.height * 0.55));
      expect(right - left, greaterThan(scene.width * 0.7));
      expect(bottom, greaterThan(scene.height * 0.8));

      double textY(String label) => scene.nodes
          .whereType<SceneText>()
          .firstWhere((node) => node.text.contains(label))
          .y;
      double textX(String label) => scene.nodes
          .whereType<SceneText>()
          .firstWhere((node) => node.text.contains(label))
          .x;
      expect(textY('X-03'), greaterThan(textY('Order entered late')));
      expect(textX('X-03'), greaterThan(textX('Order entered late') + 40));
      expect(sceneToSvg(scene), contains('<path'));
    });

    test('a branching tree spreads children instead of indenting them', () {
      final scene = buildTreeScene(
        bullets: [
          'Customer need — **Y-01**',
          '\tOn-time delivery',
          '\tComplete paperwork',
          '\tReachable support',
        ],
        layout: TreeLayout.tree,
        measurer: const ApproximateTextMeasurer(),
        title: 'CTQ',
      );
      final cards = scene.nodes
          .whereType<SceneRect>()
          .where((rect) => rect.width > 80)
          .toList();
      expect(cards, hasLength(4));
      final root = scene.nodes.whereType<SceneText>().firstWhere(
        (node) => node.text.contains('Customer need'),
      );
      final leaves =
          ['On-time delivery', 'Complete paperwork', 'Reachable support'].map(
            (label) => scene.nodes.whereType<SceneText>().firstWhere(
              (node) => node.text.contains(label),
            ),
          );
      for (final leaf in leaves) {
        expect(leaf.y, greaterThan(root.y + 24));
      }
      final xs = leaves.map((leaf) => leaf.x).toList()..sort();
      expect(xs.last - xs.first, greaterThan(scene.width * 0.4));
    });

    test('theme palette keeps light text off a light card', () {
      final dark = treePaletteFromTheme(
        background: '#0F172A',
        text: '#F8FAFC',
        accent: '#60A5FA',
      );
      expect(dark.ink, '#F8FAFC');
      expect(dark.onAccent, '#0F172A');
      expect(dark.box.toUpperCase(), isNot('#F4F7FB'));

      final light = treePaletteFromTheme(
        background: '#FFFFFF',
        text: '#0F172A',
        accent: '#003399',
      );
      expect(light.ink, '#0F172A');
      expect(light.onAccent, '#FFFFFF');

      final broken = treePaletteFromTheme(
        background: 'nope',
        text: '#112233',
        accent: '#003399',
      );
      expect(broken.ink, '#112233');
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
