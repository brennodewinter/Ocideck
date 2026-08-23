import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/editors/chart_editor.dart';

/// Dubbelklik-bewerken van een grafiek in de documentmodus (DOCUMENT_MODE.md
/// §4.2): een gerenderde ```chart-grafiek dubbelklikken opent de volwaardige
/// [ChartEditor], en 'Toepassen' schrijft het bewerkte blok terug op zijn plek
/// in de bron. De terugschrijf-logica (`replaceNthChartBlock`) is puur en wordt
/// hier los, uitputtend getoetst; de widgettest bewijst de bedrading.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget editorApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  String chartBlock(String title) {
    final spec = ChartSpec(
      type: ChartType.bar,
      title: title,
      x: const ['A', 'B'],
      series: const [
        ChartSeries(name: 'S', data: [1.0, 2.0]),
      ],
    );
    return '```chart\n${spec.toBlock()}\n```';
  }

  group('replaceNthChartBlock', () {
    test('vervangt het n-de blok en laat de rest byte-getrouw staan', () {
      final source =
          '# Rapport\n\n${chartBlock('Een')}\n\ntussentekst\n\n'
          '${chartBlock('Twee')}\n';

      final next = replaceNthChartBlock(source, 1, 'RUW-TWEE');

      // Het tweede blok is vervangen door de kale spec-tekst, in een verse fence.
      expect(next, contains('```chart\nRUW-TWEE\n```'));
      // Het eerste blok en alle omringende tekst blijven onaangeroerd.
      expect(next, contains(chartBlock('Een')));
      expect(next, contains('# Rapport'));
      expect(next, contains('tussentekst'));
      // 'Twee' zat alleen in het vervangen blok en is dus weg.
      expect(next, isNot(contains('Twee')));
    });

    test('ordinaal 0 raakt het eerste blok, niet het tweede', () {
      final source = '${chartBlock('Een')}\n\n${chartBlock('Twee')}\n';

      final next = replaceNthChartBlock(source, 0, 'RUW-EEN');

      expect(next, contains('```chart\nRUW-EEN\n```'));
      expect(next, contains(chartBlock('Twee')));
      expect(next, isNot(contains('Een')));
    });

    test('een ordinaal buiten bereik laat de bron ongemoeid', () {
      final source = '${chartBlock('Een')}\n';

      expect(replaceNthChartBlock(source, 5, 'X'), source);
    });
  });

  testWidgets('dubbelklik op de grafiek opent de editor en past het toe', (
    tester,
  ) async {
    // Breed genoeg voor de naast-elkaar-indeling met de weergave rechts.
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Rapport\n\n${chartBlock('Omzet')}\n'),
      );
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    // Embed-kaarten (SVG + potlood) leven in de Bron-weergave; Visueel is het
    // bewerkbare schrijfoppervlak.
    await tester.tap(find.text('Bron'));
    await tester.pump();

    // De grafiek rendert als SVG in de weergave.
    final chart = find.byType(SvgPicture);
    expect(chart, findsOneWidget);

    // Dubbelklik: twee tikken binnen de dubbelklik-tijd.
    final center = tester.getCenter(chart);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // De volwaardige grafiek-editor staat nu in een dialoog, met de titel erin.
    expect(find.byType(ChartEditor), findsOneWidget);
    final titleField = find.widgetWithText(TextField, 'Omzet');
    expect(titleField, findsOneWidget);

    // Bewerk de titel en pas toe → het blok wordt teruggeschreven in de bron.
    await tester.enterText(titleField, 'Omzet Q4');
    await tester.pump();
    await tester.tap(find.text('Toepassen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final source = n.currentState.document!.source;
    expect(source, contains('Omzet Q4'));
    // Nog steeds precies één grafiekblok, en de omringende tekst staat er nog.
    expect('```chart'.allMatches(source).length, 1);
    expect(source, contains('# Rapport'));
  });

  testWidgets('het potlood is zichtbaar en opent met één klik de editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Rapport\n\n${chartBlock('Omzet')}\n'),
      );
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.tap(find.text('Bron'));
    await tester.pump();

    // Het potlood-knopje is zichtbaar op de embed (ontdekbaarheid: geen
    // dubbelklik nodig) en opent met één klik dezelfde volwaardige editor.
    final pencil = find.byIcon(Icons.edit_outlined);
    expect(pencil, findsOneWidget);
    await tester.tap(pencil);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ChartEditor), findsOneWidget);
  });
}
