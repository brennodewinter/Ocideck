import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/oversized_import_warning_dialog.dart';

/// De waarschuwing bij een presentatie die groter is dan de aanbevolen limiet.
///
/// Wat hier bewaakt wordt is een keuze, geen opmaak: de gebruiker moet
/// uitdrukkelijk kiezen om een groot bestand te importeren, en Annuleren moet
/// dat echt tegenhouden. De waarschuwingstekst noemt zowel de bestandsgrootte
/// als de limiet, zodat de gebruiker kan inschatten hoe ver hij eroverheen gaat.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Pompt een scherm met één knop die de waarschuwing opent; de uitkomst
  /// wordt in [uitkomst] bewaard zodra de dialoog sluit.
  Future<List<bool>> pump(WidgetTester tester) async {
    final uitkomst = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => uitkomst.add(
                await showOversizedImportWarning(
                  context,
                  fileSize: 800 * 1024 * 1024,
                  limit: 512 * 1024 * 1024,
                ),
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    return uitkomst;
  }

  testWidgets('noemt de bestandsgrootte en de limiet', (tester) async {
    await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.text('Groot bestand'), findsOneWidget);
    expect(find.textContaining('800 MiB'), findsOneWidget);
    expect(find.textContaining('512 MiB'), findsOneWidget);
  });

  testWidgets('Annuleren geeft false', (tester) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [false]);
  });

  testWidgets('Toch importeren geeft true', (tester) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toch importeren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [true]);
  });
}
