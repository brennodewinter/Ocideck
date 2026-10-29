import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het Opslaan/Annuleren-contract voor stijlprofielen en documentopmaak
/// (#2648) — hetzelfde contract als de app-thema's al hadden (#760).
///
/// Aanmaken, importeren en verwijderen van een stijlprofiel schreven meteen
/// naar de provider en naar schijf; de documentopmaak-schakelaars en
/// -velden eveneens. Annuleren sloot het venster maar liet de wijziging
/// gelden. Nu werken allebei op een bewerkkopie die pas bij Opslaan landt.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const eigen = ThemeProfile(name: 'Eigen huisstijl');
  const tweede = ThemeProfile(name: 'Tweede huisstijl');

  late ProviderContainer container;

  Future<void> openDialog(
    WidgetTester tester, {
    required SettingsSection section,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({...prefs});
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
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

  Future<void> annuleer(WidgetTester tester) =>
      tik(tester, find.widgetWithText(TextButton, 'Annuleren'));

  Future<void> slaOp(WidgetTester tester) =>
      tik(tester, find.widgetWithText(ElevatedButton, 'Opslaan'));

  AppSettings instellingen() => container.read(settingsProvider);

  group('stijlprofielen', () {
    testWidgets('Annuleren na + laat verzameling en selectie ongemoeid', (
      tester,
    ) async {
      await openDialog(tester, section: SettingsSection.presentation);
      final before = instellingen().themeProfiles.length;
      final selectedBefore = instellingen().selectedThemeProfileName;

      await tik(tester, find.byTooltip('Nieuw profiel').first);
      await annuleer(tester);

      final settings = instellingen();
      expect(settings.themeProfiles, hasLength(before));
      expect(settings.selectedThemeProfileName, selectedBefore);
    });

    testWidgets('Opslaan na + bewaart en selecteert het nieuwe profiel', (
      tester,
    ) async {
      await openDialog(tester, section: SettingsSection.presentation);
      final before = instellingen().themeProfiles.length;

      await tik(tester, find.byTooltip('Nieuw profiel').first);
      await slaOp(tester);

      final settings = instellingen();
      expect(settings.themeProfiles, hasLength(before + 1));
      expect(
        settings.themeProfiles.map((p) => p.name),
        contains(settings.selectedThemeProfileName),
      );
    });

    testWidgets('Annuleren na verwijderen laat het profiel staan', (
      tester,
    ) async {
      await openDialog(
        tester,
        section: SettingsSection.presentation,
        prefs: {
          'themeProfiles': jsonEncode([eigen.toJson(), tweede.toJson()]),
          'selectedThemeProfileName': 'Eigen huisstijl',
        },
      );

      await tik(tester, find.byTooltip('Profiel verwijderen'));
      await annuleer(tester);

      expect(
        instellingen().themeProfiles.map((p) => p.name),
        contains('Eigen huisstijl'),
      );
      expect(instellingen().selectedThemeProfileName, 'Eigen huisstijl');
    });

    testWidgets('Opslaan na verwijderen is het profiel weg', (tester) async {
      // Twee profielen: het enige opgeslagen profiel is niet te verwijderen
      // (replaceThemeProfiles weigert een lege verzameling).
      await openDialog(
        tester,
        section: SettingsSection.presentation,
        prefs: {
          'themeProfiles': jsonEncode([eigen.toJson(), tweede.toJson()]),
          'selectedThemeProfileName': 'Eigen huisstijl',
        },
      );

      await tik(tester, find.byTooltip('Profiel verwijderen'));
      await slaOp(tester);

      final settings = instellingen();
      expect(
        settings.themeProfiles.map((p) => p.name),
        isNot(contains('Eigen huisstijl')),
      );
      // De selectie wijst weer naar een profiel dat bestaat.
      expect(
        settings.themeProfiles.map((p) => p.name),
        contains(settings.selectedThemeProfileName),
      );
    });
  });

  group('documentopmaak', () {
    Future<void> toggle(WidgetTester tester, String title) =>
        tik(tester, find.widgetWithText(SwitchListTile, title).last);

    testWidgets('Annuleren laat afdwinging, paginabreak en marge ongemoeid', (
      tester,
    ) async {
      await openDialog(
        tester,
        section: SettingsSection.general,
        prefs: {'documentDefaultStyle': 'Standaard'},
      );
      final marginsBefore = instellingen().documentPageMargins;

      await toggle(tester, 'Deze stijl afdwingen');
      await toggle(tester, 'Nieuw hoofdstuk op een nieuwe pagina');
      final margin = find.widgetWithText(TextFormField, 'Boven (mm)');
      await tester.ensureVisible(margin);
      await tester.enterText(margin, '42');
      await tester.pumpAndSettle();
      await annuleer(tester);

      final settings = instellingen();
      expect(settings.documentStyleEnforced, isFalse);
      expect(settings.documentChapterPageBreak, isTrue);
      expect(settings.documentPageMargins, marginsBefore);
    });

    testWidgets('Opslaan past de documentopmaak één keer toe', (tester) async {
      await openDialog(
        tester,
        section: SettingsSection.general,
        prefs: {'documentDefaultStyle': 'Standaard'},
      );

      await toggle(tester, 'Deze stijl afdwingen');
      await toggle(tester, 'Nieuw hoofdstuk op een nieuwe pagina');
      await slaOp(tester);

      final settings = instellingen();
      expect(settings.documentStyleEnforced, isTrue);
      expect(settings.documentChapterPageBreak, isFalse);
      expect(settings.documentDefaultStyle, 'Standaard');
    });
  });
}
