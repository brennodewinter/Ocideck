import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_l10n;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

void main() {
  testWidgets(
    'klikken tussen cellen in grote documenttabel houdt de scrollplek',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1300, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      AppLocalizations.setActiveLanguageCode('nl');

      final table = [
        '| Naam | Waarde |',
        '| --- | --- |',
        for (var i = 0; i < 250; i++) '| Rij $i | Waarde $i |',
      ].join('\n');
      final notifier = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('# Rapport\n\n$table\n'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [documentProvider.overrideWith((_) => notifier)],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              flutter_l10n.GlobalCupertinoLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DocumentEditorScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final first = find.widgetWithText(TextField, 'Rij 200');
      final second = find.widgetWithText(TextField, 'Rij 201');
      await Scrollable.ensureVisible(tester.element(second), alignment: 0.9);
      await tester.pump();
      final scrollable = Scrollable.of(tester.element(find.byType(Table)));
      final before = scrollable.position.pixels;
      final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
      final selection = quill.controller.selection;
      await tester.tap(first, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scrollable.position.pixels, closeTo(before, 2));
      expect(quill.controller.selection, selection);
      expect(
        tester.widget<TextField>(first).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(second, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scrollable.position.pixels, closeTo(before, 2));
      expect(quill.controller.selection, selection);
      expect(
        tester.widget<TextField>(second).focusNode!.hasPrimaryFocus,
        isTrue,
      );

      final tableView = find.byType(DocumentMarkdownView);
      final beforeView = tester.widget<DocumentMarkdownView>(tableView);
      quill.controller.replaceText(0, 0, 'Extra ', quill.controller.selection);
      await tester.pump();
      expect(
        identical(tester.widget<DocumentMarkdownView>(tableView), beforeView),
        isTrue,
      );

      await tester.tap(find.text('Rapport'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(quill.focusNode.hasFocus, isTrue);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
