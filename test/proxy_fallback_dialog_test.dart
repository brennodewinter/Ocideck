import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/proxy_fallback_dialog.dart';

/// De vraag die vóór de fetch-terugval staat.
///
/// De terugval geeft de volledige URL aan de origin die de app serveert — een
/// partij die de gebruiker niet aanwees, en een deellink draagt zijn sleutel in
/// het adres. Vroeger gebeurde dat automatisch en zonder melding. Deze tests
/// bewaken de kant die telt: alles behalve een uitdrukkelijk "ja" is een nee.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Opent de dialoog vanaf een knop en onthoudt wat de Future teruggaf.
  Future<bool?> openAndAnswer(
    WidgetTester tester, {
    required Future<void> Function(WidgetTester) interact,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ProxyFallbackDialog.show(
                  context,
                  host: 'elders.example',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Doorgaan geeft toestemming', (tester) async {
    final answer = await openAndAnswer(
      tester,
      interact: (t) => t.tap(find.text('Doorgaan')),
    );
    expect(answer, isTrue);
  });

  testWidgets('Annuleren geeft géén toestemming', (tester) async {
    final answer = await openAndAnswer(
      tester,
      interact: (t) => t.tap(find.text('Annuleren')),
    );
    expect(answer, isFalse);
  });

  testWidgets('wegklikken telt als nee, niet als ja', (tester) async {
    // De kant die telt. Een dialoog die bij het wegtikken `null` teruggeeft en
    // waar de aanroeper `?? true` op doet, is precies de fail-open die deze
    // vraag moest wegnemen.
    final answer = await openAndAnswer(
      tester,
      interact: (t) async {
        Navigator.of(t.element(find.byType(AlertDialog))).pop();
      },
    );
    expect(answer, isFalse);
  });

  testWidgets('de tekst zegt wat er gebeurt en wat de website ziet', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProxyFallbackDialog(host: 'elders.example')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Via deze website ophalen?'), findsOneWidget);
    // Geen jargon: de gebruiker hoeft "proxy" en "CORS" niet te kennen.
    final body = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(body.toLowerCase(), isNot(contains('proxy')));
    expect(body.toLowerCase(), isNot(contains('cors')));
    // En het noemt wél de consequentie die de gebruiker moet wegen.
    expect(body, contains('volledige adres'));
  });
}
