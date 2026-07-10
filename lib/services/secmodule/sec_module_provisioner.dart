// Provisioning engine for the Informatieveiligheid module data pack
// (PENTEST_MIAUW.md §6).
//
// Fetches a content-addressed pack across an ordered mirror list, verifies the
// downloaded bytes' sha256 against the value compiled into the app
// ([SecModuleProvisioner.expectedHash]), unpacks + verifies the inner MANIFEST
// (sec_pack_codec.dart), and caches it locally keyed by pack version — so the
// module is offline-after-first-fetch.
//
// Fallback chain (all behind the outbound-privacy consent + the module toggle):
//   1. verified local cache  → offline, NO fetch;
//   2. baseline pack across mirrors by hash;
//   3. manual local-file import ([provisionFromBytes]).
// (An opt-in upstream refresh is out of scope for the skeleton.)
//
// Both the network layer ([SecPackTransport]) and the on-disk cache
// ([SecPackStore]) are INJECTED, so tests exercise fetch/verify/cache with a
// fake transport + a fixture pack and never touch the network or a real disk.
// The class itself is pure Dart (no dart:io / Flutter): the default io/web
// implementations live in sec_pack_platform.dart.
import 'dart:typed_data';

import '../../utils/log.dart';
import 'sec_pack_codec.dart';
import 'sec_pack_config.dart';

/// Outcome of a fetch attempt against one mirror.
class SecPackFetchResult {
  final Uint8List? bytes;

  /// When [bytes] is null: whether the platform simply cannot fetch (web), as
  /// opposed to a per-mirror failure worth trying the next mirror for.
  final bool unsupported;

  const SecPackFetchResult.ok(Uint8List this.bytes) : unsupported = false;
  const SecPackFetchResult.failed() : bytes = null, unsupported = false;
  const SecPackFetchResult.unsupportedPlatform()
    : bytes = null,
      unsupported = true;

  bool get isOk => bytes != null;
}

/// Injectable network layer. The default implementation reuses the SSRF-hardened
/// pinned-socket / no-redirect / byte-capped `HttpClient`; the web
/// implementation reports [SecPackFetchResult.unsupportedPlatform].
abstract class SecPackTransport {
  /// Fetch [url], capped at [maxBytes]. Never throws — failures come back as a
  /// non-ok [SecPackFetchResult].
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes});
}

/// Injectable local cache for the unpacked pack, keyed by version. The default
/// implementation writes under the app-support directory via the atomic-file
/// helpers; tests use an in-memory store.
abstract class SecPackStore {
  /// The pack version currently cached and verified, or null when nothing is
  /// cached. A stored version is only reported when its recorded outer hash
  /// still matches [expectedHash].
  Future<String?> cachedVersion({
    required String version,
    required String expectedHash,
  });

  /// Persist the verified [contents] of the pack that hashed to [outerHash]
  /// under [version]. Replaces any previous cache for that version.
  Future<void> save({
    required String version,
    required String outerHash,
    required SecPackContents contents,
  });

  /// Remove any cached pack (the "clean up" action).
  Future<void> clear();
}

/// Where a successful provision got its data from, or why it did not.
enum SecProvisionStatus {
  /// Already present in the verified local cache — no fetch happened.
  alreadyCached,

  /// Fetched from a mirror, verified and cached.
  fetched,

  /// Verified + cached from a user-supplied local file.
  imported,

  /// No outbound consent yet, so no fetch was attempted.
  noConsent,

  /// This platform cannot fetch the pack (web) and nothing was cached.
  unsupportedPlatform,

  /// Every mirror failed or returned bytes that did not match the pinned hash.
  allMirrorsFailed,

  /// Bytes were obtained but their outer sha256 did not match the pin.
  hashMismatch,

  /// Bytes matched the outer hash but the pack was malformed / failed its inner
  /// integrity check — nothing cached.
  invalidPack,
}

/// Result of a provisioning run.
class SecProvisionResult {
  final SecProvisionStatus status;

  /// The provisioned pack version when [isProvisioned] is true.
  final String? version;

  /// The mirror URL that served the pack, when [status] is
  /// [SecProvisionStatus.fetched].
  final String? mirror;

  const SecProvisionResult(this.status, {this.version, this.mirror});

  /// Whether the module is usable after this run (cache present + verified).
  bool get isProvisioned =>
      status == SecProvisionStatus.alreadyCached ||
      status == SecProvisionStatus.fetched ||
      status == SecProvisionStatus.imported;
}

/// Drives the fetch → verify → cache pipeline. Construct with the platform
/// transport/store (sec_pack_platform.dart) or fakes (tests).
class SecModuleProvisioner {
  final SecPackTransport transport;
  final SecPackStore store;

  /// The pack version this build expects; cache is keyed by it.
  final String version;

  /// The outer sha256 the fetched/imported bytes must match — the app's pin.
  final String expectedHash;

  /// Ordered mirror URLs, tried in order.
  final List<String> mirrors;

  final int maxBytes;

  SecModuleProvisioner({
    required this.transport,
    required this.store,
    this.version = secPackVersion,
    this.expectedHash = secPackSha256,
    this.mirrors = secPackMirrors,
    this.maxBytes = secPackMaxBytes,
  });

  /// True when a verified pack for [version] is already cached.
  Future<bool> isProvisioned() async {
    final cached = await store.cachedVersion(
      version: version,
      expectedHash: expectedHash,
    );
    return cached == version;
  }

  /// Run the fallback chain. [hasConsent] gates every outbound fetch: without
  /// it, only the local cache is consulted.
  Future<SecProvisionResult> provision({required bool hasConsent}) async {
    if (await isProvisioned()) {
      return SecProvisionResult(
        SecProvisionStatus.alreadyCached,
        version: version,
      );
    }
    if (!hasConsent) {
      return const SecProvisionResult(SecProvisionStatus.noConsent);
    }
    return _fetchAcrossMirrors();
  }

  /// Verify + cache a pack the user supplied as a local file (fallback #3, and
  /// the air-gapped path). Not gated by consent: no bytes leave the device.
  Future<SecProvisionResult> provisionFromBytes(List<int> bytes) async {
    final outer = secPackSha256Hex(bytes);
    if (outer != expectedHash) {
      return const SecProvisionResult(SecProvisionStatus.hashMismatch);
    }
    final contents = _openVerified(bytes);
    if (contents == null) {
      return const SecProvisionResult(SecProvisionStatus.invalidPack);
    }
    await store.save(version: version, outerHash: outer, contents: contents);
    return SecProvisionResult(SecProvisionStatus.imported, version: version);
  }

  /// Drop the cached pack.
  Future<void> cleanUp() => store.clear();

  Future<SecProvisionResult> _fetchAcrossMirrors() async {
    var sawUnsupported = false;
    var sawHashMismatch = false;
    for (final raw in mirrors) {
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      final fetch = await transport.fetch(uri, maxBytes: maxBytes);
      if (fetch.unsupported) {
        sawUnsupported = true;
        continue;
      }
      if (!fetch.isOk) continue;
      final bytes = fetch.bytes!;
      if (secPackSha256Hex(bytes) != expectedHash) {
        // Content-addressed: a mismatch means this mirror served the wrong or a
        // tampered artefact. Try the next mirror rather than trusting it.
        sawHashMismatch = true;
        continue;
      }
      final contents = _openVerified(bytes);
      if (contents == null) {
        return const SecProvisionResult(SecProvisionStatus.invalidPack);
      }
      await store.save(
        version: version,
        outerHash: expectedHash,
        contents: contents,
      );
      return SecProvisionResult(
        SecProvisionStatus.fetched,
        version: version,
        mirror: raw,
      );
    }
    if (sawUnsupported && !sawHashMismatch) {
      return const SecProvisionResult(SecProvisionStatus.unsupportedPlatform);
    }
    if (sawHashMismatch) {
      return const SecProvisionResult(SecProvisionStatus.hashMismatch);
    }
    return const SecProvisionResult(SecProvisionStatus.allMirrorsFailed);
  }

  /// Second integrity layer: open + verify the inner MANIFEST. Returns null (a
  /// rejection, nothing cached) on any malformed / tampered pack.
  SecPackContents? _openVerified(List<int> bytes) {
    try {
      return openAndVerifySecPack(bytes, maxBytes: maxBytes);
    } on SecPackFormatException catch (e) {
      logWarning('SecModuleProvisioner: pakket afgekeurd', e);
      return null;
    }
  }
}
