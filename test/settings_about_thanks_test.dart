import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/reader/document_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het hartje naast de OciDeck-naam in "Over OciDeck" is het enige aanknoppunt
/// in de app voor het dankwoord. Deze test bewaakt dat het er staat en dat een
/// klik de leesweergave op `CONTRIBUTORS.md` opent — de banner-regels worden al
/// door settings_about_cat_photo_test gerenderd, maar de klikroute niet.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('het hartje in "Over OciDeck" opent het dankwoord', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Naar "Over OciDeck": de eerste info-knop is de zijbalktab.
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    // Het hartje staat in de banner bovenaan, herkenbaar aan zijn tooltip.
    final heart = find.byTooltip('Met dank aan');
    expect(heart, findsOneWidget);

    await tester.tap(heart);
    // Geen pumpAndSettle: de reader toont een voortgangsspinner terwijl de asset
    // laadt, en die draait eindeloos. Een vaste pump laat de route-animatie af.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final reader = tester.widget<DocumentReaderScreen>(
      find.byType(DocumentReaderScreen),
    );
    expect(reader.assetBase, 'CONTRIBUTORS.md');
    expect(reader.title, 'Met dank aan');
  });
}
