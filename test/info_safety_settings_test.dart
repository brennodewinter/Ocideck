import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "Informatieveiligheid" card in Settings → Uitbreidingen.
///
/// This file used to drive the card through provisioning failures (no mirror
/// reachable, hash mismatch, invalid pack) and assert each recourse. None of
/// that exists any more: the reference data ships inside the app, so switching
/// the module on reveals it — there is nothing to fetch, retry, import or clean
/// up, and therefore no failure to explain.
///
/// What is worth pinning is the claim the card now makes to the user: the data
/// is here, it stays here, and *this much* of it is here. The counts come from
/// the real catalogs (SecReferenceInventory), so a card that renders them is a
/// card telling the truth.
///
/// The card lives in the settings dialog's modules tab, an offstage child of an
/// IndexedStack until selected — so we render the dialog and match with
/// `skipOffstage: false` rather than fighting the tab navigation.
Future<void> _showDialog(WidgetTester tester, {required bool enabled}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SettingsDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (enabled) {
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
      listen: false,
    );
    await container.read(infoSafetyProvider.notifier).enable();
    await tester.pumpAndSettle();
  }
}

/// Unmount the tree so the ProviderScope disposes its container — which cancels
/// the tabs autosave timer, satisfying the pending-timer invariant.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('enabling the module shows what is locally available', (
    tester,
  ) async {
    await _showDialog(tester, enabled: true);

    expect(
      find.text(
        'Gegevens lokaal beschikbaar — het opzoeken gebeurt op dit apparaat, '
        'er gaat niets naar buiten.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text('Wat er lokaal beschikbaar is', skipOffstage: false),
      findsOneWidget,
    );

    await _teardownTree(tester);
  });

  testWidgets('the card offers no fetch, retry, import or cleanup', (
    tester,
  ) async {
    await _showDialog(tester, enabled: true);

    // Anchor on something that must be there, so the absences below mean "not
    // on a rendered card" rather than "no card rendered at all".
    expect(
      find.text('Wat er lokaal beschikbaar is', skipOffstage: false),
      findsOneWidget,
    );

    // Every one of these was an affordance over a pipeline that fetched
    // nothing, cached bytes nobody read, and could not fail. A button that
    // works harder at pretending is still pretending.
    for (final gone in const [
      'Opnieuw proberen',
      'Nu bijwerken',
      'Pakket importeren',
      'Gegevens opschonen',
      'Nog niet opgehaald',
    ]) {
      expect(
        find.text(gone, skipOffstage: false),
        findsNothing,
        reason: '"$gone" belongs to the removed provisioning pipeline.',
      );
    }

    await _teardownTree(tester);
  });

  testWidgets('while the module is off the card stays a bare toggle', (
    tester,
  ) async {
    await _showDialog(tester, enabled: false);

    expect(
      find.text('Informatieveiligheid', skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.text('Wat er lokaal beschikbaar is', skipOffstage: false),
      findsNothing,
    );

    await _teardownTree(tester);
  });
}
