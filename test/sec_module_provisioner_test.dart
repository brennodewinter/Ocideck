import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_module_provisioner.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/services/secmodule/sec_pack_config.dart';

/// The provisioner's fallback chain, focused on the app-bundled baseline pack:
/// it provisions offline and without consent, a stale bundle is ignored, and
/// only then is a mirror consulted.
class _FailTransport implements SecPackTransport {
  @override
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes}) async =>
      const SecPackFetchResult.failed();
}

class _MemStore implements SecPackStore {
  String? _version;
  String? _hash;
  SecPackContents? _contents;

  @override
  Future<String?> cachedVersion({
    required String version,
    required String expectedHash,
  }) async => (_version == version && _hash == expectedHash) ? version : null;

  @override
  Future<SecPackContents?> read({
    required String version,
    required String expectedHash,
  }) async => (_version == version && _hash == expectedHash) ? _contents : null;

  @override
  Future<void> save({
    required String version,
    required String outerHash,
    required SecPackContents contents,
  }) async {
    _version = version;
    _hash = outerHash;
    _contents = contents;
  }

  @override
  Future<void> clear() async {
    _version = null;
    _hash = null;
    _contents = null;
  }
}

void main() {
  // The whole point of bundling: the app ships a pack that provisioning can
  // actually use. This fails loudly if the asset is undeclared in pubspec or
  // drifts from the pinned hash (rebuild with tool/build_secmodule_pack.dart).
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the bundled baseline asset is declared and matches the pin', () async {
    final data = await rootBundle.load(secPackAssetKey);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(secPackSha256Hex(bytes), secPackSha256);
  });

  final packBytes = buildSecPack(
    packVersion: 'test-1',
    files: [
      SecPackDataFile(
        name: 'cwe/cwe.json',
        bytes: Uint8List.fromList(utf8.encode('{"k":1}')),
        upstreamVersion: 'v',
        licence: 'L',
        source: 'https://example.test/',
      ),
    ],
  );
  final hash = secPackSha256Hex(packBytes);

  SecModuleProvisioner make({
    Future<Uint8List?> Function()? bundled,
    String? expectedHash,
    List<String> mirrors = const [],
  }) => SecModuleProvisioner(
    transport: _FailTransport(),
    store: _MemStore(),
    bundledPackLoader: bundled,
    version: 'test-1',
    expectedHash: expectedHash ?? hash,
    mirrors: mirrors,
  );

  test('provisions from the bundled pack offline, without consent', () async {
    final p = make(bundled: () async => packBytes);
    final result = await p.provision(hasConsent: false);
    expect(result.status, SecProvisionStatus.bundled);
    expect(result.isProvisioned, isTrue);
    expect(await p.isProvisioned(), isTrue);
  });

  test('no bundle, no consent → noConsent (nothing revealed)', () async {
    final p = make(bundled: () async => null);
    final result = await p.provision(hasConsent: false);
    expect(result.status, SecProvisionStatus.noConsent);
  });

  test('no bundle, consent, failing mirror → allMirrorsFailed', () async {
    final p = make(bundled: () async => null, mirrors: const ['https://x/y']);
    final result = await p.provision(hasConsent: true);
    expect(result.status, SecProvisionStatus.allMirrorsFailed);
  });

  // Zonder de force-vlag stuit "Nu bijwerken" meteen op de cache en doet niets:
  // een knop die doet alsof hij ververst.
  test('a second provision short-circuits on the cache', () async {
    final p = make(bundled: () async => packBytes);
    expect(
      (await p.provision(hasConsent: false)).status,
      SecProvisionStatus.bundled,
    );
    expect(
      (await p.provision(hasConsent: false)).status,
      SecProvisionStatus.alreadyCached,
    );
  });

  test('force re-runs the chain instead of returning alreadyCached', () async {
    final p = make(bundled: () async => packBytes);
    await p.provision(hasConsent: false);

    final refreshed = await p.provision(hasConsent: false, force: true);
    expect(refreshed.status, SecProvisionStatus.bundled);
    expect(refreshed.status, isNot(SecProvisionStatus.alreadyCached));
    expect(await p.isProvisioned(), isTrue);
  });

  test('a stale bundle (hash mismatch) is ignored and falls through', () async {
    // expectedHash differs from the bundle's real hash → bundle rejected.
    final p = make(
      bundled: () async => packBytes,
      expectedHash: 'f' * 64,
      mirrors: const ['https://x/y'],
    );
    expect(
      (await p.provision(hasConsent: false)).status,
      SecProvisionStatus.noConsent,
    );
    expect(
      (await p.provision(hasConsent: true)).status,
      SecProvisionStatus.allMirrorsFailed,
    );
  });
}
