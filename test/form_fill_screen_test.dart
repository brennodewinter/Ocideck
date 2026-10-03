// De invulstand in de documenteditor: een formulierdocument opent als invulpagina,
// elk antwoord is een bewerking van het document (opslaan, ongedaan maken en de
// andere standen werken mee), en een gewoon document krijgt de stand niet.

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String formulier = '''<!-- form id=f version=1 -->
# Aanmelding

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

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
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  Future<DocumentNotifier> open(WidgetTester tester, String text) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(text));
    await tester.pumpWidget(harness(n));
    await tester.pump();
    return n;
  }

  testWidgets('een formulier opent als invulpagina, met de stand Invullen', (
    tester,
  ) async {
    await open(tester, formulier);
    expect(find.byType(FormFillView), findsOneWidget);
    expect(find.text('Invullen'), findsOneWidget);
    expect(find.text('Aanmelding'), findsWidgets);
    expect(find.textContaining('<!--'), findsNothing);
  });

  testWidgets('de invulpagina van een tabblad kan de inzending opslaan', (
    tester,
  ) async {
    final doc = '---\ntitle: Kook\n---\n$formulier';
    await open(tester, doc);
    final view = tester.widget<FormFillView>(find.byType(FormFillView));
    expect(view.export, isNotNull);
    expect(view.export!.frontMatter, '---\ntitle: Kook\n---\n');
    expect(find.text('Inzending opslaan als zip…'), findsOneWidget);
  });

  testWidgets('een gewoon document krijgt de stand niet', (tester) async {
    await open(tester, '# Kop\n\nTekst.\n');
    expect(find.byType(FormFillView), findsNothing);
    expect(find.text('Invullen'), findsNothing);
  });

  testWidgets('een antwoord is een bewerking van het document', (tester) async {
    final n = await open(tester, formulier);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    expect(
      n.state.document!.body,
      contains('<!-- answer -->\nSari\n<!-- /field id=naam -->'),
    );
    expect(n.state.canUndo, isTrue);
  });

  testWidgets('ongedaan maken haalt het antwoord uit het veld', (tester) async {
    final n = await open(tester, formulier);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    await tester.tap(find.byTooltip('Ongedaan maken'));
    await tester.pump();
    expect(n.state.document!.body, formulier);
    expect(find.widgetWithText(TextField, 'Sari'), findsNothing);
  });

  testWidgets('een heel woord typen is één stap ongedaan maken', (
    tester,
  ) async {
    final n = await open(tester, formulier);
    for (final deel in ['S', 'Sa', 'Sar', 'Sari']) {
      await tester.enterText(find.byType(TextField).first, deel);
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Ongedaan maken'));
    await tester.pump();
    expect(n.state.document!.body, formulier);
  });

  testWidgets('wisselen naar Bron en terug houdt het antwoord', (tester) async {
    final n = await open(tester, formulier);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    await tester.tap(find.text('Bron'));
    await tester.pump();
    expect(find.byType(FormFillView), findsNothing);
    expect(find.textContaining('Sari'), findsWidgets);
    await tester.tap(find.text('Invullen'));
    await tester.pump();
    expect(find.byType(FormFillView), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Sari'), findsOneWidget);
    expect(n.state.document!.body, contains('Sari'));
  });

  testWidgets(
    'Visueel opent het formulier zonder terug te vallen op brontekst',
    (tester) async {
      await open(tester, formulier);
      await tester.tap(find.text('Visueel'));
      await tester.pump();
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.textContaining('Bronmodus beschermt opmaak'), findsNothing);
    },
  );

  testWidgets('een formulier dat kapot raakt wijst naar de bron', (
    tester,
  ) async {
    final n = await open(tester, formulier);
    // Een sluitmarker weg: dat kan in Bron en dan hoort Invullen te zeggen waarom het niet kan.
    n.edit(formulier.replaceFirst('<!-- /field id=naam -->\n', ''));
    await tester.pump();
    expect(
      find.text('Dit formulier kan niet worden ingevuld.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Naar de bron'));
    await tester.pump();
    expect(find.byType(FormFillView), findsNothing);
  });
}
