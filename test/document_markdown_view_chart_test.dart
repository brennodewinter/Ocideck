import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

/// De documentweergave rendert een ```chart-blok als grafiek (statische SVG,
/// dezelfde renderlaag als de HTML-export) — de eerste stap van de visuele
/// modus (DOCUMENT_MODE.md §4.2). Zonder inline cijfers valt hij terug op de
/// bron als codeblok in plaats van een leeg vlak.
void main() {
  Widget host(String markdown) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DocumentMarkdownView(markdown)),
    ),
  );

  testWidgets('een ```chart met inline cijfers rendert als grafiek', (
    tester,
  ) async {
    final spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: const ['A', 'B'],
      series: const [
        ChartSeries(name: 'S', data: [1.0, 2.0]),
      ],
    );
    final markdown = '# Rapport\n\n```chart\n${spec.toBlock()}\n```\n';

    await tester.pumpWidget(host(markdown));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    // Zonder bewerk-callback (de docs-lezer) is er geen potlood-affordance.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('een ```chart zonder inline cijfers valt terug op het codeblok', (
    tester,
  ) async {
    const markdown =
        '```chart\n{ "type": "bar", "source": "data/x.json" }\n```\n';

    await tester.pumpWidget(host(markdown));
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    // De bron blijft zichtbaar als codeblok in plaats van een leeg vlak.
    expect(find.textContaining('source'), findsWidgets);
  });

  testWidgets('de eerste info-token selecteert ook met extra metadata chart', (
    tester,
  ) async {
    final spec = ChartSpec(
      type: ChartType.bar,
      x: const ['A'],
      series: const [
        ChartSeries(name: 'S', data: [1.0]),
      ],
    );
    await tester.pumpWidget(host('```chart extra\n${spec.toBlock()}\n```\n'));
    await tester.pump();
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  test('een vier-teken-fence laat tekst na de afsluiting renderen', () {
    final blocks = DocumentMarkdownView.blockTexts(
      '````text\n```\ncode\n````\nNA_DE_FENCE\n',
    );
    expect(blocks, contains('NA_DE_FENCE'));
  });
}
