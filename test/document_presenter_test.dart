// Widget-tests voor de documentpresentatie (#2487): alleen aangewezen
// tabellen zijn live bewerkbaar, een bevestigde edit patcht de bron via
// dezelfde chirurgische route als de documenteditor, en het afsluiten
// dwingt de bewaar-/kopie-/verwerpkeuze af.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

const _doc = '''
# Rapport

| Risico | Score |
|---|---|
| Brand | 5 |

---

# Deel 2

gewone tekst
''';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: child,
);

/// Duwt het presentatorscherm over een launcher en levert het
/// afsluitresultaat terug via [resultHolder] — zo meet de test wat de
/// afsluitkeuze opleverde.
Widget _overLauncher(
  List<DocumentPresentationResult?> resultHolder, {
  Set<int> editableTables = const {},
}) => _host(
  Builder(
    builder: (ctx) => ElevatedButton(
      onPressed: () async => resultHolder.add(
        await Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => DocumentPresenterScreen(
              body: _doc,
              themeProfile: null,
              projectPath: null,
              editableTables: editableTables,
            ),
          ),
        ),
      ),
      child: const Text('open'),
    ),
  ),
);

void main() {
  testWidgets('paginatie en paginanavigatie volgen de bron', (tester) async {
    final resultHolder = <DocumentPresentationResult?>[];
    await tester.pumpWidget(_overLauncher(resultHolder));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.textContaining('2 / 2'), findsOneWidget);
    expect(find.text('gewone tekst'), findsOneWidget);
  });

  testWidgets('E zonder aanwijzing opent niets, met aanwijzing wel', (
    tester,
  ) async {
    // Geen aanwijzing: E mag de tabel nooit impliciet bewerkbaar maken.
    await tester.pumpWidget(
      _host(
        const DocumentPresenterScreen(
          body: _doc,
          themeProfile: null,
          projectPath: null,
          editableTables: {},
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // Wél aangewezen: E opent de bewerkmodus van de tabel.
    await tester.pumpWidget(
      _host(
        const DocumentPresenterScreen(
          body: _doc,
          themeProfile: null,
          projectPath: null,
          editableTables: {0},
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Brand'), findsOneWidget);
  });

  testWidgets('bewaarde sessie-edit komt chirurgisch in de body terug', (
    tester,
  ) async {
    final resultHolder = <DocumentPresentationResult?>[];
    await tester.pumpWidget(_overLauncher(resultHolder, editableTables: {0}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Open de bewerkmodus en pas de scorecel aan.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '5'), '8');
    await tester.pump();
    // Esc verlaat de bewerkmodus, niet de presentatie.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // Nogmaals Esc: de afsluitkeuze verschijnt.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Presentatie afsluiten'), findsOneWidget);
    await tester.tap(find.text('Bewaren in document'));
    await tester.pumpAndSettle();

    final result = resultHolder.single;
    expect(result, isNotNull);
    expect(result!.choice, DocumentExitChoice.keep);
    expect(result.body, contains('| Brand | 8 |'));
    expect(result.body, contains('# Deel 2'));
  });

  testWidgets('verwerpen geeft de onaangetaste body terug', (tester) async {
    final resultHolder = <DocumentPresentationResult?>[];
    await tester.pumpWidget(_overLauncher(resultHolder, editableTables: {0}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '5'), '9');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerpen'));
    await tester.pumpAndSettle();
    final result = resultHolder.single;
    expect(result!.choice, DocumentExitChoice.discard);
    expect(result.body, contains('| Brand | 5 |'));
  });
}
