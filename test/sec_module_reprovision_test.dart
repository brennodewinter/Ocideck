import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_module_provisioner.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/services/secmodule/sec_pack_config.dart';
import 'package:ocideck/state/sec_module_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On web the cache store persists nothing, so a page reload used to drop the
/// module's provisioned marker while the enabled toggle stayed on — the module
/// silently lost its slide types and commands. The notifier now re-provisions
/// from the bundled pack on init so it re-reveals instead of disappearing.
class _NoStore implements SecPackStore {
  @override
  Future<String?> cachedVersion({
    required String version,
    required String expectedHash,
  }) async => null;
  @override
  Future<SecPackContents?> read({
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

class _NoTransport implements SecPackTransport {
  @override
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes}) async =>
      const SecPackFetchResult.unsupportedPlatform();
}

/// Web-like: the cache never reports a version (nothing persisted), but a
/// provision succeeds from the bundled pack (offline, no consent).
class _WebLikeProvisioner extends SecModuleProvisioner {
  _WebLikeProvisioner() : super(transport: _NoTransport(), store: _NoStore());

  @override
  Future<bool> isProvisioned() async => false;

  @override
  Future<SecProvisionResult> provision({
    required bool hasConsent,
    bool force = false,
  }) async =>
      SecProvisionResult(SecProvisionStatus.bundled, version: secPackVersion);
}

void main() {
  testWidgets('re-reveals on init when enabled but the cache is empty', (
    tester,
  ) async {
    // Enabled toggle persisted (as after a reload), but the cache is empty.
    SharedPreferences.setMockInitialValues({
      'secModuleEnabled': true,
      'app_consent_accepted': false,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secModuleProvisionerProvider.overrideWith(
            (ref) => _WebLikeProvisioner(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final revealed = ref.watch(secModuleRevealProvider);
            return Text('revealed=$revealed', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bundled re-provisioning restored the reveal without any user action.
    expect(find.text('revealed=true'), findsOneWidget);
  });
}
