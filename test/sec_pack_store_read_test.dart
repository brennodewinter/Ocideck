import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/services/secmodule/sec_pack_platform_io.dart';
import 'package:path/path.dart' as p;

/// FileSecPackStore is the read side of the pack cache: save() persists the
/// unpacked pack plus its manifest, and read() reconstructs and re-verifies it
/// so the module's consumers can pull the reference data back — while a cache
/// that was tampered with on disk is refused rather than served.
void main() {
  late Directory tmp;
  late FileSecPackStore store;

  const version = 'test-1';
  const outerHash = 'deadbeef';

  SecPackContents buildContents() => openAndVerifySecPack(
    buildSecPack(
      packVersion: version,
      files: [
        SecPackDataFile(
          name: 'cwe/cwe.json',
          bytes: Uint8List.fromList('{"hello":"cwe"}'.codeUnits),
          upstreamVersion: '4.20',
          licence: 'CC-BY',
          source: 'MITRE',
        ),
      ],
    ),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('secpack_read_test');
    store = FileSecPackStore(baseDir: Directory(p.join(tmp.path, 'secmodule')));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('save then read round-trips the data files and the manifest', () async {
    await store.save(
      version: version,
      outerHash: outerHash,
      contents: buildContents(),
    );

    final back = await store.read(version: version, expectedHash: outerHash);
    expect(back, isNotNull);
    expect(back!.files.keys, contains('cwe/cwe.json'));
    expect(
      String.fromCharCodes(back.files['cwe/cwe.json']!),
      '{"hello":"cwe"}',
    );
    expect(back.manifest.packVersion, version);
    expect(back.manifest.files.single.source, 'MITRE');
  });

  test('read returns null when the outer-hash marker does not match', () async {
    await store.save(
      version: version,
      outerHash: outerHash,
      contents: buildContents(),
    );
    expect(await store.read(version: version, expectedHash: 'other'), isNull);
  });

  test('read returns null when nothing was saved for the version', () async {
    expect(await store.read(version: version, expectedHash: outerHash), isNull);
  });

  test('read refuses a cache whose data file was tampered on disk', () async {
    await store.save(
      version: version,
      outerHash: outerHash,
      contents: buildContents(),
    );
    // Corrupt the persisted file so its sha256 no longer matches the manifest.
    final f = File(p.join(tmp.path, 'secmodule', version, 'cwe', 'cwe.json'));
    await f.writeAsString('{"hello":"tampered"}');
    expect(await store.read(version: version, expectedHash: outerHash), isNull);
  });
}
