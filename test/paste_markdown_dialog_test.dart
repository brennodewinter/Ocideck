import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/paste_markdown_dialog.dart';

/// De "Plak Markdown…"-dialoog (#2825). De openpoort zelf
/// (`TabsNotifier.openDeckFromBytes`) staat in
/// `open_deck_from_bytes_test.dart`; hier ligt wat de dialoog toebehoort:
/// de knop pas aan bij echte tekst, de tekst die bij een weigering blijft
/// staan, en de bevestiging vóór iemand zijn plaksel weggooit.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Opent de dialoog vanaf een knop. [onOpenResult] is wat de gespeelde
  /// openpoort teruggeeft: `null` voor "geopend", anders de melding.
  Future<void> openDialog(
    WidgetTester tester, {
    String? onOpenResult,
    List<String>? captured,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PasteMarkdownDialog.show(
                context,
                onOpen: (text) async {
                  captured?.add(text);
                  return onOpenResult;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder openButton() => find.widgetWithText(FilledButton, 'Open in OciDeck');

  testWidgets('Open-knop uit bij leeg én bij alleen witruimte', (tester) async {
    await openDialog(tester);
    expect(tester.widget<FilledButton>(openButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   \n\t  ');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(openButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '# Titel');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(openButton()).onPressed, isNotNull);
  });

  testWidgets('tekens-teller loopt mee met de invoer', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'abcde');
    await tester.pumpAndSettle();
    expect(find.text('5 tekens'), findsOneWidget);
  });

  testWidgets('geslaagde open sluit de dialoog en geeft de tekst door', (
    tester,
  ) async {
    final captured = <String>[];
    await openDialog(tester, captured: captured);
    await tester.enterText(find.byType(TextField), '---\nmarp: true\n---\n# X');
    await tester.pumpAndSettle();
    await tester.tap(openButton());
    await tester.pumpAndSettle();
    expect(captured, ['---\nmarp: true\n---\n# X']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('een weigering houdt dialoog én tekst vast en toont de melding', (
    tester,
  ) async {
    await openDialog(tester, onOpenResult: 'Dit bestand is te groot.');
    await tester.enterText(find.byType(TextField), 'ongeldig');
    await tester.pumpAndSettle();
    await tester.tap(openButton());
    await tester.pumpAndSettle();
    // AC6: de tekst blijft staan zodat hij te corrigeren of te kopiëren is.
    expect(find.text('Dit bestand is te groot.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ongeldig',
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
    'annuleren met tekst vraagt bevestiging; weigeren houdt hem open',
    (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'werk');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.text('Geplakte tekst verwerpen?'), findsOneWidget);
      // "Annuleren" in de bevestiging = terug naar de tekst. Twee dialogen
      // dragen die knop: neem die van de bevestiging.
      await tester.tap(find.text('Annuleren').last);
      await tester.pumpAndSettle();
      expect(find.text('Geplakte tekst verwerpen?'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'werk',
      );
      // "Verwerpen" gooit de tekst weg en sluit.
      await tester.tap(find.text('Annuleren').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerpen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('annuleren met een leeg veld sluit meteen', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
