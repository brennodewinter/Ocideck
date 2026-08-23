import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/state/procesverbetering_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/procesverbetering_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Procesverbetering module Phase 0: switch on Uitbreidingen, off by default,
/// category + discovery stubs ready for engine types (PROCESS_IMPROVEMENT.md).
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('de stand en de poort', () {
    Future<ProviderContainer> vers({
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(procesverbeteringProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test('een verse installatie start uit en verborgen', () async {
      final c = await vers();
      expect(c.read(procesverbeteringEnabledProvider), isFalse);
      expect(c.read(procesverbeteringRevealProvider), isFalse);
    });

    test('aanzetten onthult de module', () async {
      final c = await vers();
      await c.read(procesverbeteringProvider.notifier).setEnabled(true);
      expect(c.read(procesverbeteringEnabledProvider), isTrue);
      expect(c.read(procesverbeteringRevealProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('procesverbeteringModuleEnabled'), isTrue);
    });

    test('het register bevat Procesverbetering', () {
      expect(
        moduleRegistry.map((m) => m.id),
        contains(ModuleId.procesverbetering),
      );
    });
  });

  group('deck discovery stubs', () {
    test('zonder engine-types is hasImprovementSlides false', () {
      final deck = Deck(
        title: 'Test',
        slides: [const Slide(id: 's1', type: SlideType.title, title: 'Hallo')],
      );
      expect(deck.hasImprovementSlides, isFalse);
      expect(deck.firstImprovementSlideIndex, -1);
    });

    test('een matrix-slide onthult hasImprovementSlides', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          const Slide(id: 's1', type: SlideType.title, title: 'Hallo'),
          Slide.create(SlideType.matrix),
        ],
      );
      expect(deck.hasImprovementSlides, isTrue);
      expect(deck.firstImprovementSlideIndex, 1);
    });

    test('SlideCategory kent procesverbetering', () {
      expect(SlideCategory.values, contains(SlideCategory.procesverbetering));
    });
  });

  group('het instellingenvenster', () {
    testWidgets('Uitbreidingen toont de Procesverbetering-kaart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
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
      expect(find.byType(ProcesverbeteringModuleCard), findsOneWidget);
      expect(find.text('Procesverbetering'), findsWidgets);
      expect(find.byType(SwitchListTile), findsNWidgets(moduleRegistry.length));
    });
  });
}
