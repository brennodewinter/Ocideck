import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/improvement/matrix_layout.dart';
import 'package:ocideck/services/improvement/matrix_slide.dart';
import 'package:ocideck/services/improvement/matrix_spec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/scene/scene.dart';

void main() {
  group('matrix slide', () {
    test('fresh matrix starts as SIPOC with English header contract', () {
      final slide = Slide.create(SlideType.matrix);
      expect(slide.improvementTemplateId, kDefaultImprovementTemplateId);
      expect(slide.tableRows.first, [
        'Supplier',
        'Input',
        'Process',
        'Output',
        'Customer',
      ]);
    });

    test('FMEA RPN is derived, ranked high-first, never stored', () {
      final slide = Slide.create(SlideType.matrix).copyWith(
        improvementTemplateId: 'fmea',
        tableRows: [
          matrixHeaderRow(
            bundledImprovementTemplates.firstWhere((t) => t.id == 'fmea'),
          ),
          ['a', 'fail', 'effect', '3', 'cause', '2', 'ctrl', '2'],
          ['b', 'fail', 'effect', '9', 'cause', '8', 'ctrl', '7'],
        ],
      );
      expect(matrixRowRpn(slide, slide.tableRows[2]), 504);
      expect(matrixDisplayRows(slide).first[0], 'b');
      final md = MarkdownService().generateDeck(
        Deck(title: 'T', slides: [slide]),
      );
      expect(md, contains('ocideck_template: fmea'));
      expect(md, isNot(contains('| 504 |')));
      expect(md, isNot(contains('RPN')));
    });

    test('Markdown round-trip keeps template id and rows', () {
      final original = Slide.create(SlideType.matrix).copyWith(
        title: 'Order intake',
        improvementTemplateId: 'sipoc',
        tableRows: [
          ['Supplier', 'Input', 'Process', 'Output', 'Customer'],
          ['CRM', 'Lead', 'Qualify', 'Opportunity', 'Sales'],
        ],
      );
      final md = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [original]),
      );
      final parsed = MarkdownService().parseDeck(md)!.slides.single;
      expect(parsed.type, SlideType.matrix);
      expect(parsed.improvementTemplateId, 'sipoc');
      expect(parsed.title, 'Order intake');
      expect(parsed.tableRows, original.tableRows);
    });

    test('switching template remaps shared column keys', () {
      final sipoc = Slide.create(SlideType.matrix).copyWith(
        improvementTemplateId: 'sipoc',
        tableRows: [
          ['Supplier', 'Input', 'Process', 'Output', 'Customer'],
          ['CRM', 'Lead', 'Qualify', 'Opportunity', 'Sales'],
        ],
      );
      final remapped = matrixRowsForTemplate(sipoc, 'fmea');
      expect(remapped.first, contains('Process step'));
      // Process column shared by key name? sipoc has process, fmea has step —
      // only exact key matches move. Process≠step, so cells start empty except
      // what happens to share keys. Supplier etc. do not exist on FMEA.
      expect(remapped[1].every((c) => c.isEmpty), isTrue);
    });

    test('scene builds SVG with derived RPN cell', () {
      final slide = Slide.create(SlideType.matrix).copyWith(
        title: 'FMEA',
        improvementTemplateId: 'fmea',
        tableRows: [
          matrixHeaderRow(
            bundledImprovementTemplates.firstWhere((t) => t.id == 'fmea'),
          ),
          ['step', 'mode', 'effect', '7', 'cause', '6', 'ctrl', '5'],
        ],
      );
      final scene = buildMatrixScene(
        spec: matrixSpecFromSlide(slide),
        displayColumns: matrixDisplayColumns(slide),
        rows: matrixDisplayRows(slide),
        measurer: const ApproximateTextMeasurer(),
        title: slide.title,
      );
      final svg = sceneToSvg(scene);
      expect(svg, contains('<svg'));
      expect(svg, contains('210'));
      expect(svg, contains('RPN'));
    });

    test('HTML export replaces the table with the scene SVG', () {
      final md = '''
<!-- _class: matrix -->
<!-- ocideck_template: fmea -->
# FMEA

| Process step | Failure mode | Effect | S | Cause | O | Control | D |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Intake | Miss | Delay | 7 | Rush | 6 | Check | 5 |
''';
      final out = renderMatrixSlide(md);
      expect(out, contains('<svg'));
      expect(out, contains('210'));
      expect(out, isNot(contains('| Intake |')));
    });
  });
}
