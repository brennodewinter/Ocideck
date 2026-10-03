import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/forms_provider.dart';
import 'package:ocideck/state/integration_registry.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/forms_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De uitbreiding Formulieren en inzendingen (FORM_INTAKE.md §7): een schakelaar op
/// Uitbreidingen, standaard uit, die de organisatorkant onthult — en een werkmap die
/// hem zichtbaar houdt ook als de schakelaar uitgaat.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('de stand en de poort', () {
    Future<ProviderContainer> vers({
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(formsProvider);
      container.read(formsWorkspaceProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test(
      'een verse installatie start uit, zonder werkmap, verborgen',
      () async {
        final c = await vers();
        expect(c.read(formsEnabledProvider), isFalse);
        expect(c.read(formsWorkspaceProvider), isNull);
        expect(c.read(formsRevealProvider), isFalse);
      },
    );

    test('aanzetten onthult de functie en bewaart de voorkeur', () async {
      final c = await vers();
      await c.read(formsProvider.notifier).setEnabled(true);
      expect(c.read(formsEnabledProvider), isTrue);
      expect(c.read(formsRevealProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('formsModuleEnabled'), isTrue);
    });

    test('een bewaarde voorkeur wordt bij het opstarten gelezen', () async {
      final c = await vers(prefs: {'formsModuleEnabled': true});
      expect(c.read(formsEnabledProvider), isTrue);
    });

    test('een gekozen werkmap wordt bewaard en teruggelezen', () async {
      final c = await vers();
      await c.read(formsWorkspaceProvider.notifier).choose('/tmp/werkmap');
      expect(c.read(formsWorkspaceProvider), '/tmp/werkmap');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('formsWorkspacePath'), '/tmp/werkmap');

      final next = await vers(prefs: {'formsWorkspacePath': '/tmp/werkmap'});
      expect(next.read(formsWorkspaceProvider), '/tmp/werkmap');
    });

    test(
      'met een werkmap blijft de functie zichtbaar als de schakelaar uit staat',
      () async {
        final c = await vers(prefs: {'formsWorkspacePath': '/tmp/werkmap'});
        expect(c.read(formsEnabledProvider), isFalse);
        expect(c.read(formsRevealProvider), isTrue);
      },
    );

    test('een lege bewaarde werkmap telt niet', () async {
      final c = await vers(prefs: {'formsWorkspacePath': ''});
      expect(c.read(formsWorkspaceProvider), isNull);
      expect(c.read(formsRevealProvider), isFalse);
    });

    test('het register bevat Formulieren, als laatste', () {
      expect(moduleRegistry.last.id, ModuleId.forms);
    });
  });

  group('het instellingenvenster', () {
    testWidgets('toont de kaart en de schakelaar werkt', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late ProviderContainer container;
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
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
      expect(find.byType(FormsModuleCard), findsOneWidget);
      expect(find.text('Formulieren en inzendingen'), findsWidgets);
      expect(
        find.byType(SwitchListTile),
        findsNWidgets(moduleRegistry.length + integrationRegistry.length),
      );

      final tile = find.descendant(
        of: find.byType(FormsModuleCard),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(container.read(formsEnabledProvider), isTrue);
    });
  });
}
