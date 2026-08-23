@TestOn('vm')
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/import_module_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/import_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De module Importeren (#772, B1) na #1158: sinds OpenKAT is losgemaakt tot een
/// eigen integratie gaat deze module nog over één bron — de presentatie-import
/// (.pptx/.key/.odp). Standaard uit, en haar reveal is nu simpelweg de
/// schakelaar: de presentatie-import laat niets persistents achter, dus er is
/// geen inhoud die het invoerpunt na het uitzetten bereikbaar hoeft te houden.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> vers({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({...prefs});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(importModuleProvider);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('een nieuwe installatie start uit', () async {
    final c = await vers();
    expect(c.read(importModuleEnabledProvider), isFalse);
    expect(c.read(importModuleRevealProvider), isFalse);
  });

  test('de keuze van de gebruiker wordt bewaard en onthult de bron', () async {
    final c = await vers();
    await c.read(importModuleProvider.notifier).setEnabled(true);
    expect(
      (await SharedPreferences.getInstance()).getBool('importModuleEnabled'),
      isTrue,
    );
    expect(c.read(importModuleRevealProvider), isTrue);
  });

  test(
    'de reveal volgt de schakelaar: er is geen persistente inhoud',
    () async {
      // OpenKAT bracht de enige inhoud in; na de losmaking is de lijst leeg.
      expect(importerContentProviders, isEmpty);
      final c = await vers();
      expect(c.read(importHasContentProvider), isFalse);
    },
  );

  // #1209: de schakelaar wordt asynchroon uit SharedPreferences geladen. Een
  // beslissing die vlak na de start valt — de "wat nu"-melding bij het openen,
  // slepen of web-openen van een presentatie — mag niet op de nog-ladende
  // default vallen en de module als uit zien terwijl hij aan staat.
  test(
    'de reveal-wacht ziet de opgeslagen stand, de kale lezing nog niet',
    () async {
      SharedPreferences.setMockInitialValues({'importModuleEnabled': true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Eerste lezing, nog vóór het async laden klaar is: precies het venster
      // waarin #1209 de verkeerde melding toonde — de veilige default (uit).
      expect(c.read(importModuleRevealProvider), isFalse);
      // Na het wachten op de notifier is de opgeslagen stand er: module aan.
      await c.read(importModuleProvider.notifier).ready;
      expect(c.read(importModuleRevealProvider), isTrue);
    },
  );

  testWidgets('de open-helper wacht op het laden en ziet de module aan (#1209)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'importModuleEnabled': true});
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    // Op het eerste frame leest de kale reveal nog de ladende default: dit is
    // het startvenster waarin de melding de gebruiker naar de instellingen
    // stuurde voor een module die al aan stond.
    expect(captured.read(importModuleRevealProvider), isFalse);
    // De helper die de open-/sleep-/web-paden gebruiken wacht dat venster af en
    // geeft de werkelijke stand terug: aan.
    await expectLater(
      importModuleRevealedWhenReady(captured),
      completion(isTrue),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('de kaart schakelt de module en noemt OpenKAT niet meer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportModuleCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Importeren'), findsOneWidget);
    final schakelaar = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(schakelaar).value, isFalse);
    await tester.tap(schakelaar);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(schakelaar).value, isTrue);
  });
}
