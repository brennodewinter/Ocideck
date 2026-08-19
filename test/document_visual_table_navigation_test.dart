import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// Toetsen in een tabelcel van de **visuele** documentmodus (#1565).
///
/// De cel is een tekstveld binnen een Quill-embed. Quill zet zijn eigen
/// tekstbewerkingsacties in een [Actions] boven de embed, en die overschreven
/// die van de cel: één pijl in een tabel liet Quill de cursor van het document
/// verzetten en dat resultaat ín de cel schrijven. De hele documenttekst
/// belandde met `<br>`-tekens in één cel, en omdat die tekens rauwe HTML zijn
/// viel de visuele stand stil terug op brontekst — zonder dat er iets te zien
/// was.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget editorApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  const bron =
      '# Rapport\n\n'
      '| Naam | Waarde |\n| --- | --- |\n| Alfa | 1 |\n| Beta | 2 |\n\n'
      'Slot.\n';

  Future<DocumentNotifier> openInDeCel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(bron));
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.showKeyboard(find.widgetWithText(TextField, 'Alfa'));
    await tester.pump();
    return n;
  }

  testWidgets('pijl omlaag door de tabel houdt de visuele stand', (
    tester,
  ) async {
    final n = await openInDeCel(tester);

    // Twee rijen omlaag en dan nog één keer: de laatste valt op de onderrand
    // van de tabel, en juist die liep vroeger door naar Quill.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    // Nog steeds de rijke-tekstweergave, niet de brontekst-terugval.
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(markdownVisualLimitations(n.currentState.document!.body), isEmpty);
    // En de cellen staan er nog zoals ze stonden: geen documenttekst die in een
    // cel is geplakt, geen `<br>`.
    expect(n.currentState.document!.source, bron);
    expect(find.widgetWithText(TextField, 'Beta'), findsOneWidget);
  });

  testWidgets('pijl naar links verzet de cursor bínnen de cel', (tester) async {
    await openInDeCel(tester);
    final cel = find.widgetWithText(TextField, 'Alfa');
    final controller = tester.widget<TextField>(cel).controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    // Eén teken naar links in de cel — niet in het document, en niet niets:
    // de afscherming geeft de toets door aan het veld zelf.
    expect(controller.selection.baseOffset, 2);
    expect(controller.text, 'Alfa');
  });

  testWidgets('alleen de cursor verzetten schrijft het document niet opnieuw', (
    tester,
  ) async {
    final n = await openInDeCel(tester);
    final voor = n.currentState.document!.source;

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // De heen-en-terugweg door de rijke-tekstlaag levert niet byte-getrouw
    // dezelfde bron op; zonder de poort in de editor schreef de eerste klik het
    // hele document opnieuw weg, inclusief een stap in ongedaan maken.
    expect(n.currentState.document!.source, voor);
  });
}
