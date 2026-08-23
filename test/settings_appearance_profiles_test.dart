import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aanmaken en verwijderen van een app-thema horen het contract van het
/// instellingenvenster te volgen: alles telt pas bij Opslaan, en tot dan mag
/// Annuleren alles terugdraaien (#760).
///
/// De twee knopjes naast de themakiezer schreven rechtstreeks naar de provider
/// en naar schijf — één rij met twee soorten gedrag, en een Annuleren-knop die
/// maar één van de twee terugdraaide. De prullenbak was bovendien definitief
/// zonder vraag, en de terugval na verwijderen was de hardgecodeerde 'Europa'
/// terwijl de dialoog 'Basic' koos: met Annuleren hield je Europa, met Opslaan
/// kreeg je Basic, en geen van beide was waar je vandaan kwam.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const eigen = AppAppearanceProfile(
    name: 'Eigen thema',
    isDark: true,
    primaryColor: '#111827',
    accentColor: '#60A5FA',
    backgroundColor: '#0F172A',
    surfaceColor: '#1E293B',
    textColor: '#F1F5F9',
    mutedTextColor: '#94A3B8',
    panelColor: '#090E1A',
    panelTextColor: '#E2E8F0',
  );

  late ProviderContainer container;

  Future<void> openAppearance(
    WidgetTester tester, {
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
                  onPressed: () => SettingsDialog.show(
                    context,
                    initialSection: SettingsSection.appearance,
                  ),
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

  Finder plusKnop() => find.byTooltip('Kopie maken en aanpassen');
  Finder prullenbak() => find.byTooltip('Thema verwijderen');

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

  testWidgets('Annuleren na + laat geen profiel achter en schakelt niet', (
    tester,
  ) async {
    await openAppearance(tester);
    await tik(tester, plusKnop());
    await annuleer(tester);

    // Het profiel hoort weg te zijn, en het actieve thema onveranderd — vóór
    // #760 stond "Eigen thema" er nog én was het het actieve thema geworden.
    expect(
      instellingen().appAppearanceProfiles.map((p) => p.name),
      isNot(contains('Eigen thema')),
    );
    expect(instellingen().selectedAppAppearanceProfileName, 'Europa');
  });

  testWidgets('Opslaan na + bewaart het profiel wél', (tester) async {
    // De tegenproef: zonder deze zou de groep ook slagen als de + niets meer
    // deed.
    await openAppearance(tester);
    await tik(tester, plusKnop());
    await slaOp(tester);

    expect(
      instellingen().appAppearanceProfiles.map((p) => p.name),
      contains('Eigen thema'),
    );
    expect(instellingen().selectedAppAppearanceProfileName, 'Eigen thema');
  });

  testWidgets('Annuleren na verwijderen laat het profiel staan', (
    tester,
  ) async {
    await openAppearance(
      tester,
      prefs: {
        'appAppearanceProfiles': jsonEncode([eigen.toJson()]),
        'selectedAppAppearanceProfileName': 'Eigen thema',
      },
    );
    await tik(tester, prullenbak());
    await annuleer(tester);

    expect(
      instellingen().appAppearanceProfiles.map((p) => p.name),
      contains('Eigen thema'),
    );
    expect(instellingen().selectedAppAppearanceProfileName, 'Eigen thema');
  });

  testWidgets('het actieve thema verwijderen: dialoog en instelling eens', (
    tester,
  ) async {
    await openAppearance(
      tester,
      prefs: {
        'appAppearanceProfiles': jsonEncode([eigen.toJson()]),
        'selectedAppAppearanceProfileName': 'Eigen thema',
      },
    );
    await tik(tester, prullenbak());
    await slaOp(tester);

    final s = instellingen();
    expect(
      s.appAppearanceProfiles.map((p) => p.name),
      isNot(contains('Eigen thema')),
    );
    // De terugval is een profiel dat bestáát, en dialoog en instelling wijzen
    // hetzelfde aan — vóór #760 bewaarde de provider 'Europa' terwijl de
    // dialoog 'Basic' toonde.
    expect(
      s.appAppearanceProfiles.map((p) => p.name),
      contains(s.selectedAppAppearanceProfileName),
    );
  });

  testWidgets('verwijderen valt terug op het thema van vóór de kopie', (
    tester,
  ) async {
    // Kopie maken vanaf Donker, kopie weggooien: je hoort weer in Donker te
    // staan — niet in een hardgecodeerd licht thema.
    await openAppearance(
      tester,
      prefs: {'selectedAppAppearanceProfileName': 'Donker'},
    );
    await tik(tester, plusKnop());
    await tik(tester, prullenbak());
    await slaOp(tester);

    expect(instellingen().selectedAppAppearanceProfileName, 'Donker');
  });

  testWidgets('een ingebouwd thema is niet te verwijderen', (tester) async {
    await openAppearance(tester);

    final knop = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(knop.onPressed, isNull);
  });
}
