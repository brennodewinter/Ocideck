import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De beeldkeuring vond dat een document dat zijn paginaopmaak draagt, in de
/// app alsnog op de ingestelde maat werd getoond: het scherm gaf de *body* aan
/// de resolver, en daar is de frontmatter net vanaf gehaald. De bytes reisden
/// mee, de app deed er niets mee.
///
/// Deze toets kijkt daarom op het scherm, niet op de functie eronder — daar zat
/// de fout namelijk niet.
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

  testWidgets('de indicator toont de maat die het document zelf draagt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '---\npapersize: a3\n'
          'geometry: top=30mm,bottom=30mm,left=15mm,right=15mm\n---\n\n'
          '# Kop\n\nTekst.\n',
        ),
      );
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    // A3, niet de ingestelde standaard A4 — en met de marges uit het document.
    expect(find.textContaining('A3'), findsWidgets);
    expect(find.textContaining('30/30/15/15mm'), findsWidgets);
  });

  testWidgets('een document zonder opmaak toont de instelling', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.\n'));
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    expect(find.textContaining('A4'), findsWidgets);
  });

  testWidgets('de tooltip zegt waar de opmaak vandaan komt', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('---\npapersize: a5\n---\n\n# Kop\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Deze paginaopmaak staat in dit document'),
      findsOneWidget,
      reason:
          'het speldje en de tooltip hangen aan dezelfde vraag: draagt dit '
          'document zijn eigen opmaak?',
    );
  });
}
