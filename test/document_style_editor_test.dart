import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De Stijl-kiezer in de documenteditor: kiezen zet `theme:` in de frontmatter,
/// 'Geen' haalt hem er byte-getrouw weer uit, en de body bewerken laat de stijl
/// staan. De frontmatter is nooit tekst in de editor — de kiezer beheert hem.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
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

  Future<void> pickStyle(WidgetTester tester, String item) async {
    await tester.tap(find.textContaining('Stijl:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pump();
  }

  testWidgets('een stijl kiezen schrijft `theme:` in de frontmatter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Standaard geen stijl.
    expect(find.text('Stijl: Geen'), findsOneWidget);

    await pickStyle(tester, 'Security');

    expect(n.currentState.document!.styleName, 'Security');
    expect(
      n.currentState.document!.source,
      '---\ntheme: Security\n---\n\n# Kop\n\nTekst.',
    );
    // De body (wat de editor toont) bevat de frontmatter niet.
    expect(n.currentState.document!.body, '# Kop\n\nTekst.');
    expect(find.text('Stijl: Security'), findsOneWidget);
    expect(n.currentState.isDirty, isTrue);
  });

  testWidgets("'Geen' kiezen haalt de stijl er byte-getrouw weer uit", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const plain = '# Kop\n\nTekst.';
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(plain));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await pickStyle(tester, 'LibreKAT');
    expect(n.currentState.document!.styleName, 'LibreKAT');

    await pickStyle(tester, 'Geen (platte tekst)');
    expect(n.currentState.document!.styleName, isNull);
    expect(n.currentState.document!.source, plain);
  });

  testWidgets('de body bewerken laat de stijl-frontmatter staan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await pickStyle(tester, 'LibreKAT');

    // Naar Bron: het tekstveld toont de body zónder frontmatter.
    await tester.tap(find.text('Bron'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '# Kop\n\nTekst.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '# Nieuw\n\nMeer.');
    await tester.pump();

    expect(
      n.currentState.document!.source,
      '---\ntheme: LibreKAT\n---\n\n# Nieuw\n\nMeer.',
    );
    expect(n.currentState.document!.styleName, 'LibreKAT');
  });
}
