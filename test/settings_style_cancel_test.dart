import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stijlprofielen en de documentlay-out volgen hetzelfde contract als de
/// app-thema's: ze tellen pas bij Opslaan. Annuleren laat de lijst en de
/// paginamaat zoals ze bij het openen waren.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  late ProviderContainer container;

  Future<void> open(
    WidgetTester tester, {
    SettingsSection section = SettingsSection.presentation,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                return ElevatedButton(
                  onPressed: () =>
                      SettingsDialog.show(context, initialSection: section),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.text('open')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
  }

  Future<void> tik(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('Annuleren na een nieuw stijlprofiel schrijft niets weg', (
    tester,
  ) async {
    await open(tester);
    final before = container
        .read(settingsProvider)
        .themeProfiles
        .map((profile) => profile.name)
        .toList();

    await tik(tester, find.byTooltip('Nieuw profiel').hitTestable().first);
    expect(find.text('Nieuw profiel'), findsWidgets);
    await tik(tester, find.widgetWithText(TextButton, 'Annuleren'));

    expect(
      container.read(settingsProvider).themeProfiles.map((p) => p.name),
      before,
    );
  });

  testWidgets('Annuleren laat de paginamaat staan', (tester) async {
    await open(tester, section: SettingsSection.general);
    final before = container.read(settingsProvider).documentPageSize;

    final maat = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(maat.first);
    await tester.pumpAndSettle();
    await tester.tap(maat.first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('A3').last);
    await tester.pumpAndSettle();
    await tik(tester, find.widgetWithText(TextButton, 'Annuleren'));

    expect(container.read(settingsProvider).documentPageSize, before);
    expect(before.sizeName, 'A4');
  });

  testWidgets('Opslaan bewaart een nieuw stijlprofiel', (tester) async {
    await open(tester);
    await tik(tester, find.byTooltip('Nieuw profiel').hitTestable().first);
    await tik(tester, find.widgetWithText(ElevatedButton, 'Opslaan'));

    expect(
      container
          .read(settingsProvider)
          .themeProfiles
          .map((profile) => profile.name),
      contains('Nieuw profiel'),
    );
  });
}
