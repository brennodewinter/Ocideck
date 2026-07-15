// Web implementation of the module-pack platform layer.
//
// The web build's CSP is `connect-src 'self' https:`, so HTTPS mirrors are
// permitted by CSP — the real web blocker for third-party upstreams is CORS
// (PENTEST_MIAUW.md §6 web note). Consistent with `supportsNetworkDeckSources`
// being false on web, module provisioning is DEFERRED on web: the transport
// reports the platform as unsupported and the store caches nothing, so enabling
// the module on web reveals nothing until a same-origin/CORS mirror is stood up
// (or the module code is loaded `deferred as`). No client data leaves the page.
import 'sec_module_provisioner.dart';
import 'sec_pack_codec.dart';

/// Whether this platform can provision the pack over the network. False on web.
const bool secModuleCanProvision = false;

SecPackTransport createSecPackTransport() => const _UnsupportedTransport();

SecPackStore createSecPackStore() => const _NullSecPackStore();

class _UnsupportedTransport implements SecPackTransport {
  const _UnsupportedTransport();

  @override
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes}) async =>
      const SecPackFetchResult.unsupportedPlatform();
}

class _NullSecPackStore implements SecPackStore {
  const _NullSecPackStore();

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
