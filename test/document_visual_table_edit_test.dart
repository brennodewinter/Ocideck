import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations, QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

/// De visuele stand blijft staan als je in een tabel typt (#1565).
///
/// De zusterklacht van de pijltjestoets: die is hersteld, maar het *bewerken*
/// zelf wierp het document nog steeds terug in de brontekst. Twee gewone
/// handelingen deden het al — een regeleinde in een cel (Shift+Enter, precies
/// zoals de cel het zelf aanbiedt) en een backslash typen. `encodeMarkdownTable`
/// schrijft die als `<br>` en als `\\`, de visuele poort las dat als rauwe HTML
/// en als een ontsnapping, en het schrijfvlak viel om. Zonder melding, zonder
/// weg terug — en met de modusknop nog op *visueel*.
///
/// Deze toets kijkt naar het enige dat de gebruiker ziet: staat het schrijfvlak
/// er ná de bewerking nog?
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const bron = '''
Een alinea vooraf.

| Pad | Rol |
| --- | --- |
| Aap | Tester |
''';

  /// De editor met een ouder die op de bron-controller meeluistert — zoals het
  /// documentscherm doet. Zonder die herbouw ziet de test de terugval niet, want
  /// de stand wordt bij het bouwen bepaald.
  Future<TextEditingController> pump(WidgetTester tester) async {
    final controller = TextEditingController(text: bron);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => MarkdownNotesEditor(
                controller: controller,
                editorTheme: MarkdownEditorTheme.documentSurface(
                  scheme: const ColorScheme.light(),
                ),
                hintText: '',
                expand: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Future<TextEditingController> typeInCell(
    WidgetTester tester,
    String tekst,
  ) async {
    final controller = await pump(tester);
    expect(
      find.byType(QuillEditor),
      findsOneWidget,
      reason: 'begint in de visuele stand',
    );
    // Cel 2 = de eerste cel van de gegevensrij (kop, kop, cel, cel).
    await tester.enterText(find.byType(TextField).at(2), tekst);
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('een regeleinde in een cel houdt het schrijfvlak overeind', (
    tester,
  ) async {
    final controller = await typeInCell(tester, 'Aap\nNoot');
    expect(
      controller.text,
      contains('| Aap<br>Noot |'),
      reason: 'het regeleinde wordt als `<br>` in de cel bewaard',
    );
    expect(find.byType(QuillEditor), findsOneWidget);
  });

  testWidgets('een backslash in een cel houdt het schrijfvlak overeind', (
    tester,
  ) async {
    final controller = await typeInCell(tester, r'C:\Data');
    expect(
      controller.text,
      contains(r'| C:\\Data |'),
      reason: 'de celcodering ontsnapt de backslash',
    );
    expect(find.byType(QuillEditor), findsOneWidget);
  });

  testWidgets('een gewone bewerking landt gewoon in de bron', (tester) async {
    final controller = await typeInCell(tester, 'Aapje');
    expect(controller.text, contains('| Aapje | Tester |'));
    expect(find.byType(QuillEditor), findsOneWidget);
  });
}
