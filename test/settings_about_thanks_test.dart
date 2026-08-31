import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/reader/document_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het dankwoord (`CONTRIBUTORS.md`) heeft drie ingangen in de app, en alle
/// drie zijn het klikroutes die je alleen ziet als je ze uitvoert: het hartje
/// in de banner van "Over OciDeck", de tegel naast het Vigilis-logo in datzelfde
/// tabblad, en de tegel in Documentatie. Het hartje was er eerst alleen, en dat
/// bleek te stil — één icoon zonder woord erbij is voor wie zoekt geen
/// vindplaats. Deze test bewaakt dat alle drie de ingangen er staan en op
/// hetzelfde document uitkomen.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  /// Opent de instellingen op [section]. Rechtstreeks op het tabblad en niet
  /// via de zijbalk: die lijst scrollt, en een tab die net buiten beeld valt
  /// laat `tap` op de achtergrond drukken — dan sluit het venster in plaats van
  /// dat het tabblad wisselt, en de test faalt om iets wat niet stuk is.
  Future<void> openSettings(
    WidgetTester tester, {
    required SettingsSection section,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    SettingsDialog.show(context, initialSection: section),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Laat de route-animatie aflopen zonder te settelen: de reader toont een
  /// voortgangsspinner terwijl de asset laadt, en die draait eindeloos.
  Future<void> pumpReader(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void expectThanksReader(WidgetTester tester) {
    final reader = tester.widget<DocumentReaderScreen>(
      find.byType(DocumentReaderScreen),
    );
    expect(reader.assetBase, 'CONTRIBUTORS.md');
    expect(reader.title, 'Met dank aan');
  }

  testWidgets('het hartje in "Over OciDeck" opent het dankwoord', (
    tester,
  ) async {
    await openSettings(tester, section: SettingsSection.about);

    // Het hartje staat in de banner bovenaan, herkenbaar aan zijn tooltip.
    final heart = find.byTooltip('Met dank aan');
    expect(heart, findsOneWidget);

    await tester.tap(heart);
    await pumpReader(tester);
    expectThanksReader(tester);
  });

  testWidgets('de tegel naast het Vigilis-logo opent het dankwoord', (
    tester,
  ) async {
    await openSettings(tester, section: SettingsSection.about);

    // De tegel staat onder "Mogelijk gemaakt door", diep in het tabblad.
    final tile = find.text('Met dank aan');
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    // Logo en tegel horen op één regel: op gelijke hoogte staan is de hele
    // reden dat de tegel daar hangt en niet als losse regel eronder.
    final logo = find.bySemanticsLabel('Vigilis');
    expect(logo, findsOneWidget);
    expect(
      tester.getCenter(tile).dy,
      moreOrLessEquals(tester.getCenter(logo).dy, epsilon: 1),
    );

    // En aan de andere kant van de kaart: vlak naast het logo leek de tegel
    // bij het merk te horen. Het logo houdt links, de tegel rechts.
    final row = find.ancestor(of: tile, matching: find.byType(Wrap)).first;
    final tileBox = find
        .ancestor(of: tile, matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(tileBox).right,
      moreOrLessEquals(tester.getRect(row).right, epsilon: 1),
      reason: 'de tegel hoort tegen de rechterrand van de kaart te staan',
    );
    expect(
      tester.getRect(logo).left,
      moreOrLessEquals(tester.getRect(row).left, epsilon: 1),
      reason: 'het logo hoort tegen de linkerrand van de kaart te staan',
    );

    await tester.tap(tile);
    await pumpReader(tester);
    expectThanksReader(tester);
  });

  testWidgets('het dankwoord staat als tegel in Documentatie', (tester) async {
    await openSettings(tester, section: SettingsSection.documentation);

    // De sectie "Over OciDeck" sluit de documentenlijst af, dus scrollen.
    final tile = find.text('Met dank aan');
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(tile);
    await pumpReader(tester);
    expectThanksReader(tester);
  });
}
