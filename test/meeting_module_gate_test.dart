import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/state/meetings_module_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/meetings_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De modulepoort van T13: standaard uit, onthulling is `aan || sessie
/// actief`, en uitzetten maakt een lopend gesprek nooit onbereikbaar.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> vers({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({...prefs});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(meetingsModuleProvider);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  group('de stand en de poort', () {
    test('een verse installatie start uit en verborgen', () async {
      final c = await vers();
      expect(c.read(meetingsModuleEnabledProvider), isFalse);
      expect(c.read(meetingsModuleRevealProvider), isFalse);
    });

    test('aanzetten onthult de module en bewaart de keuze', () async {
      final c = await vers();
      await c.read(meetingsModuleProvider.notifier).setEnabled(true);
      expect(c.read(meetingsModuleEnabledProvider), isTrue);
      expect(c.read(meetingsModuleRevealProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('meetingsModuleEnabled'), isTrue);
    });

    test('een bewaarde keuze wordt bij het opstarten gelezen', () async {
      final c = await vers(prefs: {'meetingsModuleEnabled': true});
      expect(c.read(meetingsModuleEnabledProvider), isTrue);
    });

    test(
      'een lopende sessie onthult de module ook als hij uit staat',
      () async {
        final c = await vers();
        expect(c.read(meetingsModuleRevealProvider), isFalse);
        // Elke fase behalve idle telt als lopend — ook een mislukte afloop die
        // de gebruiker nog moet kunnen lezen.
        c.read(meetingSessionProvider.notifier).resolveLink('geen link');
        expect(c.read(meetingSessionActiveProvider), isTrue);
        expect(c.read(meetingsModuleRevealProvider), isTrue);
        // Pas de reset laat de module weer verdwijnen.
        c.read(meetingSessionProvider.notifier).reset();
        expect(c.read(meetingsModuleRevealProvider), isFalse);
      },
    );

    test('het register kent Onlinevergaderingen', () {
      expect(moduleRegistry.map((m) => m.id), contains(ModuleId.meetings));
      final entry = moduleRegistry.singleWhere(
        (m) => m.id == ModuleId.meetings,
      );
      expect(entry.enabled, meetingsModuleEnabledProvider);
      expect(entry.revealed, meetingsModuleRevealProvider);
    });
  });

  group('de modulekaart', () {
    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: MeetingsModuleCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('de schakelaar staat uit en zet de module aan', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpCard(tester);
      expect(find.text('Onlinevergaderingen'), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('meetingsModuleEnabled'), isTrue);
      // Aan, en zonder aangesloten aanbieder belooft de voettekst niets:
      // meedoen kan nog niet, en er gaat niets naar buiten.
      expect(
        find.textContaining('nog geen vergaderdienst beschikbaar'),
        findsOneWidget,
      );
    });

    testWidgets('uit mét lopend gesprek legt uit waarom de module blijft', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: MeetingsModuleCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MeetingsModuleCard)),
      );
      container.read(meetingSessionProvider.notifier).resolveLink('geen link');
      await tester.pumpAndSettle();
      expect(find.textContaining('Er loopt een vergadering'), findsOneWidget);
    });
  });
}
