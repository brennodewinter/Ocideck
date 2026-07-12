import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_module_provisioner.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/state/sec_module_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "Informatieveiligheid" module card must explain *why* provisioning
/// failed rather than collapse every failure into one bare "Ophalen mislukt".
/// These tests drive the card through each failure status and assert the
/// distinct, human-readable message plus the manual-import recourse.
///
/// The card lives in the settings dialog's modules tab, which is an offstage
/// child of an IndexedStack until selected — so we render the dialog, drive the
/// failure through the notifier, and match with `skipOffstage: false` rather
/// than fighting the tab-navigation / overlay hit-testing.
class _NoTransport implements SecPackTransport {
  @override
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes}) async =>
      const SecPackFetchResult.failed();
}

class _NoStore implements SecPackStore {
  @override
  Future<String?> cachedVersion({
    required String version,
    required String expectedHash,
  }) async => null;
  @override
  Future<void> save({
    required String version,
    required String outerHash,
    required SecPackContents contents,
  }) async {}
  @override
  Future<void> clear() async {}
}

/// A provisioner whose every run yields a fixed [status], so the settings card
/// can be exercised without any network or disk.
class _FixedProvisioner extends SecModuleProvisioner {
  final SecProvisionStatus status;
  _FixedProvisioner(this.status)
    : super(transport: _NoTransport(), store: _NoStore());
  @override
  Future<bool> isProvisioned() async => false;
  @override
  Future<SecProvisionResult> provision({required bool hasConsent}) async =>
      SecProvisionResult(status);
}

/// Open the settings dialog, then turn the module on (which runs provisioning —
/// our fake fails with [status]). The dialog reads `tabsProvider`, whose
/// notifier starts a 25 s autosave timer; the caller must unmount the tree (see
/// [_teardownTree]) so that timer is cancelled before the test ends.
Future<void> _showDialogAndEnable(
  WidgetTester tester,
  SecProvisionStatus status,
) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secModuleProvisionerProvider.overrideWithValue(
          _FixedProvisioner(status),
        ),
      ],
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
  final container = ProviderScope.containerOf(
    tester.element(find.text('open')),
    listen: false,
  );
  await container.read(secModuleProvider.notifier).enable();
  await tester.pumpAndSettle();
}

/// Unmount the widget tree so the ProviderScope disposes its container — which
/// cancels the tabs autosave timer, satisfying the pending-timer invariant.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const cases = {
    SecProvisionStatus.allMirrorsFailed:
        'Geen bron bereikbaar — de referentiegegevens konden nergens worden '
        'opgehaald. Controleer je internetverbinding en probeer het later '
        'opnieuw.',
    SecProvisionStatus.hashMismatch:
        'De opgehaalde gegevens kwamen niet overeen met de verwachte '
        'vingerafdruk en zijn uit voorzorg geweigerd.',
    SecProvisionStatus.invalidPack:
        'Het gegevenspakket was beschadigd of ongeldig en is daarom geweigerd.',
  };

  cases.forEach((status, message) {
    testWidgets('$status shows its own message and the import recourse', (
      tester,
    ) async {
      await _showDialogAndEnable(tester, status);

      // The card renders in the (offstage) modules tab of the IndexedStack.
      expect(find.text(message, skipOffstage: false), findsOneWidget);
      // The old catch-all is gone.
      expect(find.text('Ophalen mislukt', skipOffstage: false), findsNothing);
      // The manual-import fallback is offered while nothing is revealed yet.
      expect(
        find.text('Pakket importeren', skipOffstage: false),
        findsOneWidget,
      );

      await _teardownTree(tester);
    });
  });

  testWidgets('the three failure messages are distinct', (tester) async {
    expect(cases.values.toSet().length, cases.length);
  });
}
