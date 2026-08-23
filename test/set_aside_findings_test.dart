import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/disabled_privacy_rules.dart';
import 'package:ocideck/widgets/dialogs/settings/set_aside_findings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De terzijdegelegd-lijst is de tegenkant van de knop in het kwaliteitspaneel
/// (#651). Het ontwerp stelt het scherp: een terzijdelegging die je niet
/// terugvindt is een verwijdering.
///
/// Twee dingen bewaken deze toetsen. Dat een teruggezet oordeel uit de lijst
/// verdwijnt maar níét uit de sidecar — de grafsteen is wat het samenvoegen
/// laat werken. En dat er nooit een gevonden waarde op een chip komt: die staat
/// niet in de sidecar en hoort niet in een instellingenscherm.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zout = '0123456789abcdef0123456789abcdef';
  final commitment = commitmentFor(zout, 'Jan Jansen');

  PrivacyDismissal oordeel({int minuut = 0, int? dia = 4}) => PrivacyDismissal(
    ruleId: 'contact.email',
    commitment: commitment,
    at: DateTime.utc(2026, 7, 23, 12, minuut),
    seenAtSlide: dia,
  );

  Future<void> toon(WidgetTester tester, DeckDismissals? terzijde) async {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(deckProvider.notifier)
        .loadDeck(
          Deck(
            title: 'Briefing',
            slides: [Slide.create(SlideType.title)],
            dismissals: terzijde,
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [DisabledPrivacyRules(), SetAsidePrivacyFindings()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Alleen de chips van de terzijdegelegd-lijst. `DisabledPrivacyRules` staat
  /// in dezelfde kolom en draagt er standaard al drie — de zwaarste art.
  /// 9-categorieën staan uit — dus een kale `byType(InputChip)` telt die mee.
  Finder chips() => find.descendant(
    of: find.byType(SetAsidePrivacyFindings),
    matching: find.byType(InputChip),
  );

  group('stillHidden', () {
    test('een oordeel zonder herroeping verbergt', () {
      final set = DeckDismissals(salt: zout, dismissals: [oordeel()]);
      expect(stillHidden(set, set.dismissals.single), isTrue);
    });

    test('een latere herroeping haalt het uit de lijst', () {
      final set = DeckDismissals(
        salt: zout,
        dismissals: [oordeel()],
        revocations: [oordeel(minuut: 5)],
      );
      expect(stillHidden(set, set.dismissals.single), isFalse);
    });

    test('opnieuw terzijdeleggen zet het terug in de lijst', () {
      final set = DeckDismissals(
        salt: zout,
        dismissals: [oordeel(), oordeel(minuut: 10)],
        revocations: [oordeel(minuut: 5)],
      );
      expect(stillHidden(set, set.dismissals.first), isTrue);
    });
  });

  group('het label', () {
    test('noemt de regel en de dia, nooit de waarde', () {
      const l10n = AppLocalizations(Locale('nl'));
      final label = setAsideChipLabel(l10n, oordeel());
      expect(label, contains('5'), reason: 'dia-index 4 leest als dia 5');
      expect(label, isNot(contains('Jan')));
      expect(label, isNot(contains(commitment)));
    });

    test('een deckbrede bevinding krijgt geen dianummer', () {
      const l10n = AppLocalizations(Locale('nl'));
      expect(setAsideChipLabel(l10n, oordeel(dia: null)), isNot(contains('·')));
    });
  });

  group('de lijst', () {
    testWidgets('is er niet wanneer er niets terzijde ligt', (tester) async {
      await toon(tester, null);
      expect(chips(), findsNothing);
    });

    testWidgets('toont een chip per oordeel, zonder de waarde', (tester) async {
      await toon(tester, DeckDismissals(salt: zout, dismissals: [oordeel()]));
      expect(chips(), findsOneWidget);
      expect(find.textContaining('Jan'), findsNothing);
    });

    testWidgets('een teruggezet oordeel staat er niet meer bij', (
      tester,
    ) async {
      await toon(
        tester,
        DeckDismissals(
          salt: zout,
          dismissals: [oordeel()],
          revocations: [oordeel(minuut: 5)],
        ),
      );
      expect(chips(), findsNothing);
    });
  });
}
