import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:path/path.dart' as p;

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
    expect(find.widgetWithText(TextField, '# Kop\n\nTekst.'), findsOneWidget);
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

  testWidgets('de Overzicht-rail toont de koppen en scrollt zonder crash', (
    tester,
  ) async {
    // Breed genoeg dat de rail meedoet (>= 940).
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\n## Twee\n\ntekst\n\n# Drie\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De koppen staan in de rail (eigen documenttekst, geen l10n). De weergave
    // rendert ze als RichText, de editor als één bronveld, dus find.text raakt
    // hier de rail-items.
    expect(find.text('Een'), findsWidgets);
    expect(find.text('Twee'), findsWidgets);
    expect(find.text('Drie'), findsWidgets);

    // Klikken op een kop scrollt de weergave; mag niet crashen.
    await tester.tap(find.text('Twee').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cmd+S slaat op naar het pad en maakt het document schoon', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('doc_save');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync('oud\n');

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('oud\n'), filePath: path);
    await tester.pumpWidget(harness(n));

    await tester.enterText(find.byType(TextField), 'nieuw\n');
    await tester.pump();
    expect(n.currentState.isDirty, isTrue);

    // Roep de opslag-binding rechtstreeks aan; de toets→binding-afhandeling is
    // Flutters eigen (goed geteste) CallbackShortcuts-machinerie, dus dit toetst
    // wat van ons is: dat Cmd+S aan een werkende opslag hangt. In runAsync, want
    // de atomische schrijfactie is echte schijf-IO die de test-klok niet aandrijft.
    const saveActivator = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
    final shortcuts = tester
        .widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts))
        .firstWhere((w) => w.bindings.containsKey(saveActivator));
    await tester.runAsync(() async {
      shortcuts.bindings[saveActivator]!();
      for (var i = 0; i < 50 && n.currentState.isDirty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(File(path).readAsStringSync(), 'nieuw\n');
    expect(n.currentState.isDirty, isFalse);
  });

  testWidgets(
    'Visueel maakt de weergave het hoofdoppervlak, zonder rauwe editor',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
      await tester.pumpWidget(harness(n));
      await tester.pump();

      // Standaard staat de editor in de bron-modus: de rauwe editor is er.
      expect(find.byType(TextField), findsOneWidget);

      // Wissel naar Visueel: de rauwe editor verdwijnt, de weergave blijft.
      await tester.tap(find.text('Visueel'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DocumentMarkdownView), findsOneWidget);
    },
  );

  testWidgets('het invoeg-palet schrijft een mermaid-blok in de bron', (
    tester,
  ) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Open het invoeg-palet en kies Mermaid (de enige invoeging zonder dialoog).
    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mermaid'));
    // De invoeging is synchroon; niet pumpAndSettle, want de zojuist ingevoegde
    // ```mermaid-weergave rendert asynchroon en zou de test laten aftikken.
    await tester.pump();

    // Er staat nu een ```mermaid-fence in de bron; de bestaande tekst blijft.
    final source = n.currentState.document!.source;
    expect(source, contains('```mermaid'));
    expect(source, startsWith('Tekst.'));
  });

  testWidgets(
    'de opmaak-knoppenbalk muteert de bron en stroomt naar de notifier',
    (tester) async {
      final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
      await tester.pumpWidget(harness(n));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      // 'Vet' klikken muteert de controller rechtstreeks (geen onChanged); de
      // controllerluisteraar moet dat tóch naar de notifier stromen. Met een
      // samengevouwen cursor voegt het de placeholder tussen ** ** in.
      await tester.tap(find.byTooltip('Vet'));
      await tester.pump();

      expect(n.currentState.document!.source, contains('**'));
      expect(n.currentState.isDirty, isTrue);
    },
  );
}
