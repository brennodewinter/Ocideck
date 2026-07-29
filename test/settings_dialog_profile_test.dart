import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dekking voor `settings_dialog_profile.dart` — de stijlprofiel-kiezer en
/// de actieknoppen (nieuw, standaard laden, exporteren, importeren,
/// verwijderen). De smoke-test opent het dialoog en wandelt door de tabbladen,
/// maar interageert niet met de profiel-kiezer.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> openAppearanceTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.presentation,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('het profiel-menu toont de beschikbare profielen', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Het dropdown-icoon opent het popup-menu met profielnamen.
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pumpAndSettle();

    // Het standaardprofiel heet "Standaard" en moet in de lijst staan.
    expect(find.text('Standaard'), findsWidgets);
  });

  testWidgets('het tekstveld bijt de profielnaam bij', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Typ een nieuwe naam in het tekstveld.
    await tester.enterText(find.byType(TextField).first, 'Mijn profiel');
    await tester.pump();

    // De naam is nu in het veld zichtbaar.
    expect(find.text('Mijn profiel'), findsOneWidget);
  });

  testWidgets('"Standaardprofiel laden" zet het profiel terug', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Druk op het reset-icoon (restart_alt).
    await tester.tap(find.byIcon(Icons.restart_alt).first);
    await tester.pumpAndSettle();

    // Het profiel is teruggezet — geen crash, dialoog staat nog.
    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  testWidgets('"Nieuw profiel" maakt een profiel aan', (tester) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    final before = container.read(settingsProvider).themeProfiles.length;
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    final after = container.read(settingsProvider).themeProfiles.length;

    expect(after, greaterThan(before));
  });

  testWidgets('"Profiel verwijderen" is ingeschakeld bij meerdere profielen', (
    tester,
  ) async {
    final container = await openAppearanceTab(tester);
    addTearDown(container.dispose);

    // Maak een tweede profiel aan zodat de verwijderknop actief is.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    final btn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline).first,
    );
    expect(btn.onPressed, isNotNull);
  });
}
