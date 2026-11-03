import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

void main() {
  for (final navigation in [-1, 0, 1, 2]) {
    testWidgets('weergavezoekbereik bewaart bronanker na $navigation Enter', (
      tester,
    ) async {
      AppLocalizations.setActiveLanguageCode('nl');
      await tester.binding.setSurfaceSize(const Size(1300, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const source =
          'Een gebruikte noot[^a].\n\n[^ongebruikt]: kat geheim\n\n[^a]: kat zichtbaar';
      final notifier = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse(source));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [documentProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DocumentEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bron'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoeken'));
      await tester.pumpAndSettle();
      final query = find
          .descendant(
            of: find.byType(MarkdownFindBar),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(query, 'kat');
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();
      MarkdownFindBar bar() =>
          tester.widget<MarkdownFindBar>(find.byType(MarkdownFindBar));
      expect(bar().matchCount, 2);
      for (var i = 0; i < navigation; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text("Pagina's"));
      await tester.pumpAndSettle();
      expect(bar().matchCount, 1);
      expect(bar().resultContexts.single, isNot(contains('geheim')));
      expect(bar().matchIndex, 0);
      if (navigation < 0) {
        notifier.requestFind(showReplace: true);
        await tester.pumpAndSettle();
        expect(find.byType(PagedDocumentView), findsNothing);
        expect(bar().showReplace, isTrue);
        expect(bar().matchCount, 2);
        await tester.tap(find.text("Pagina's"));
        await tester.pumpAndSettle();
        expect(bar().showReplace, isFalse);
        expect(bar().matchCount, 1);
        expect(notifier.state.document!.body, source);
        return;
      }
      final pages = tester.widget<PagedDocumentView>(
        find.byType(PagedDocumentView),
      );
      expect(
        pages.searchRevealSignal,
        navigation == 2 ? greaterThan(0) : 0,
        reason:
            'alleen het bestaande zichtbare bronanker reist mee; verdwijnen of typen springt niet',
      );
      await tester.tap(find.text('Bron'));
      await tester.pumpAndSettle();
      expect(bar().matchCount, 2);
      expect(bar().matchIndex, navigation == 2 ? 1 : 0);
      expect(notifier.state.document!.body, source);
      expect(tester.takeException(), isNull);
    });
  }
}
