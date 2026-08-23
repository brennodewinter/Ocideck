// In de browser bestaat crashherstel niet, en niets zei dat.
//
// `RecoveryService` is op web een no-op (geen app-supportmap), de autosave-tik
// start er niet eens, en er was geen `beforeunload`: een tabblad dat wegklikte
// nam het werk mee. Op desktop wérkt herstel wél, dus de gebruiker had geen
// reden te vermoeden dat het hier anders is — precies wat stilzwijgen een
// valstrik maakt.
//
// De toets hangt aan [RecoveryService.available] en niet aan `kIsWeb`: die kan
// een VM-test niet omzetten, en bovendien is "is er herstel" de echte vraag.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/platform/unsaved_work_guard.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een herstelmap die er niet is — wat de webversie feitelijk heeft.
class _NoRecovery extends RecoveryService {
  _NoRecovery() : super(baseDir: Directory.systemTemp);

  @override
  bool get available => false;

  @override
  Future<void> save(RecoverySnapshot snapshot) async {}

  @override
  Future<void> discard(String id) async {}
}

void main() {
  const notice =
      'In de browser is er geen crashherstel: sluit je dit tabblad, dan is '
      'niet-opgeslagen werk weg. Sla je presentatie zelf op.';

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Deck deck() => Deck(
    title: 'Test',
    slides: [Slide.create(SlideType.title).copyWith(title: 'Test')],
  );

  /// Zonder [recovery] draait de app met de echte dienst, die op de VM (net als
  /// op desktop) wél beschikbaar is.
  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    RecoveryService? recovery,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (recovery != null)
            recoveryServiceProvider.overrideWithValue(recovery),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  testWidgets('zonder crashherstel meldt de eerste bewerking dat', (
    tester,
  ) async {
    final container = await pumpShell(tester, recovery: _NoRecovery());
    // Nog niets gewijzigd: dan valt er ook nog niets te verliezen.
    expect(find.textContaining('geen crashherstel'), findsNothing);

    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier
      ..loadDeck(deck())
      ..markDirty();
    await tester.pumpAndSettle();

    expect(find.text(notice), findsOneWidget);
  });

  testWidgets('de mededeling komt maar één keer', (tester) async {
    final container = await pumpShell(tester, recovery: _NoRecovery());
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier
      ..loadDeck(deck())
      ..markDirty();
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(AppShell)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    // Schoon en opnieuw vuil: een herhaalde waarschuwing leert alleen maar
    // wegklikken.
    tab.deckNotifier.loadDeck(deck());
    await tester.pumpAndSettle();
    tab.deckNotifier.markDirty();
    await tester.pumpAndSettle();

    expect(find.textContaining('geen crashherstel'), findsNothing);
  });

  testWidgets('met werkend crashherstel blijft het stil', (tester) async {
    final container = await pumpShell(tester);
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier
      ..loadDeck(deck())
      ..markDirty();
    await tester.pumpAndSettle();

    expect(find.textContaining('geen crashherstel'), findsNothing);
  });

  test('de rem op het sluiten is op desktop een no-op', () {
    // De webhelft (`beforeunload`) kan een VM-test niet laden; wat hier telt is
    // dat de gevel op desktop niets omvergooit en beide standen aankan.
    expect(() {
      setUnsavedWorkGuard(true);
      setUnsavedWorkGuard(false);
    }, returnsNormally);
  });
}
