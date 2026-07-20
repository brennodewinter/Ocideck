// De strenge stand in de instellingen: staat de schakelaar er, en doet hij iets.
//
// `privacy_strict_severity_test.dart` toetst de vertaling van zekerheid naar
// ernst. Die kan kloppen terwijl de gebruiker er niet bij kan — een instelling
// die alleen in het model bestaat, bestaat voor niemand. Vandaar deze tweede
// test, die de dialoog echt opent en de schakelaar echt omzet.
//
// Alles loopt hier via de UI en niet via de provider: een eigen
// `ProviderContainer` naast de widgetboom laat de periodieke timer van
// `TabsNotifier` openstaan, en dan valt de test om op iets wat niets met deze
// instelling te maken heeft. Door de hoofdschakelaar ook aan te klikken in
// plaats van hem via de notifier te zetten, toetst de laatste test bovendien
// wat een gebruiker werkelijk doet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSecurityTab(WidgetTester tester) async {
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
                  initialSection: SettingsSection.security,
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
  }

  /// Het beveiligingstabblad is langer dan het scherm, dus de schakelaar moet
  /// eerst in beeld gerold worden — anders mist de tik zijn doel.
  Future<SwitchListTile> switchNamed(WidgetTester tester, String label) async {
    final finder = find.ancestor(
      of: find.text(label),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return tester.widget<SwitchListTile>(finder);
  }

  const strictLabel = 'Zekere vondsten als fout behandelen';
  const mainLabel = 'Waarschuw bij mogelijke persoonsgegevens';

  testWidgets('de schakelaar staat op het beveiligingstabblad, en staat uit', (
    tester,
  ) async {
    await openSecurityTab(tester);
    expect((await switchNamed(tester, strictLabel)).value, isFalse);
  });

  testWidgets('omzetten schrijft de instelling weg', (tester) async {
    await openSecurityTab(tester);
    await switchNamed(tester, strictLabel);
    await tester.tap(find.text(strictLabel));
    await tester.pumpAndSettle();

    expect((await switchNamed(tester, strictLabel)).value, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('privacyStrictSeverity'),
      isTrue,
      reason: 'de instelling overleeft een herstart niet',
    );
  });

  testWidgets('zonder privacycontrole is de schakelaar uitgegrijsd', (
    tester,
  ) async {
    await openSecurityTab(tester);
    expect((await switchNamed(tester, strictLabel)).onChanged, isNotNull);

    await switchNamed(tester, mainLabel);
    await tester.tap(find.text(mainLabel));
    await tester.pumpAndSettle();

    expect(
      (await switchNamed(tester, strictLabel)).onChanged,
      isNull,
      reason:
          'een strenge stand boven een uitgezette controle belooft iets wat '
          'niet gebeurt',
    );
  });
}
