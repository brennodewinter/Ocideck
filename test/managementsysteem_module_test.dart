import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/managementsysteem_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/managementsysteem_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Managementsysteem module (ISO_MANAGEMENTSYSTEEM §5): an opt-in switch on
/// Uitbreidingen, off by default, that reveals the `controlStatus` slide type.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('de stand en de poort', () {
    Future<ProviderContainer> vers({
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(managementsysteemProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test('een verse installatie start uit en verborgen', () async {
      final c = await vers();
      expect(c.read(managementsysteemEnabledProvider), isFalse);
      expect(c.read(managementsysteemRevealProvider), isFalse);
    });

    test('aanzetten onthult de module en bewaart de voorkeur', () async {
      final c = await vers();
      await c.read(managementsysteemProvider.notifier).setEnabled(true);
      expect(c.read(managementsysteemEnabledProvider), isTrue);
      expect(c.read(managementsysteemRevealProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('managementsysteemModuleEnabled'), isTrue);
    });

    test('een bewaarde voorkeur wordt bij het opstarten gelezen', () async {
      final c = await vers(prefs: {'managementsysteemModuleEnabled': true});
      expect(c.read(managementsysteemEnabledProvider), isTrue);
    });

    test('het register bevat Managementsysteem', () {
      expect(
        moduleRegistry.map((m) => m.id),
        contains(ModuleId.managementsysteem),
      );
    });
  });

  group('deck discovery', () {
    test('zonder controlStatus is hasManagementSystemSlides false', () {
      final deck = Deck(
        title: 'Test',
        slides: [const Slide(id: 's1', type: SlideType.title, title: 'Hallo')],
      );
      expect(deck.hasManagementSystemSlides, isFalse);
      expect(deck.firstManagementSystemSlideIndex, -1);
    });

    test('een controlStatus-slide onthult hasManagementSystemSlides', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          const Slide(id: 's1', type: SlideType.title, title: 'Hallo'),
          Slide.create(SlideType.controlStatus),
        ],
      );
      expect(deck.hasManagementSystemSlides, isTrue);
      expect(deck.firstManagementSystemSlideIndex, 1);
    });

    test('SlideCategory kent managementsysteem', () {
      expect(SlideCategory.values, contains(SlideCategory.managementsysteem));
    });
  });

  group('het instellingenvenster', () {
    testWidgets('Uitbreidingen toont de Managementsysteem-kaart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () => SettingsDialog.show(
                      context,
                      initialSection: SettingsSection.modules,
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ManagementsysteemModuleCard), findsOneWidget);
      // One switch per registered module card.
      expect(find.byType(SwitchListTile), findsNWidgets(moduleRegistry.length));
    });
  });
}
