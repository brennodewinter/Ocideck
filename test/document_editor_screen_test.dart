import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

void main() {
  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
    child: const MaterialApp(home: DocumentEditorScreen()),
  );

  testWidgets('toont de bron rauw én in een live weergave', (tester) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De rauwe editor draagt de bron letterlijk.
    expect(
      find.widgetWithText(TextField, '# Kop\n\nTekst.'),
      findsOneWidget,
    );
    // De weergave rendert dezelfde bron (robuust op de prop, niet op glyphs).
    final view = tester.widget<DocumentMarkdownView>(
      find.byType(DocumentMarkdownView),
    );
    expect(view.markdown, '# Kop\n\nTekst.');
  });

  testWidgets('typen stroomt live naar de notifier (geen Toepassen-muur)', (
    tester,
  ) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
    await tester.pumpWidget(harness(n));

    await tester.enterText(find.byType(TextField), 'Hallo wereld');
    await tester.pump();

    expect(n.currentState.document!.source, 'Hallo wereld');
    expect(n.currentState.isDirty, isTrue);
  });

  testWidgets('ongedaan maken werkt de editortekst bij', (tester) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    await tester.pumpWidget(harness(n));

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    n.undo();
    await tester.pump();

    expect(find.widgetWithText(TextField, 'a'), findsOneWidget);
  });
}
