import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/asset_rights_module_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/asset_rights_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('de uitbreiding staat standaard uit en bewaart de keuze', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(assetRightsModuleProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(assetRightsModuleEnabledProvider), isFalse);

    await container.read(assetRightsModuleProvider.notifier).setEnabled(true);
    expect(container.read(assetRightsModuleEnabledProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(assetRightsModuleEnabledKey), isTrue);
    expect(
      moduleRegistry.map((entry) => entry.id),
      contains(ModuleId.assetRights),
    );
  });

  testWidgets('de uitbreidingskaart schakelt de module aan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AssetRightsModuleCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Afbeeldingsrechten'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
