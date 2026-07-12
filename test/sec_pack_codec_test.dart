import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';

/// Tests the pure-Dart security-module data-pack codec: the build → verify
/// round-trip is byte-deterministic, and every tamper/corruption path raises a
/// [SecPackFormatException] so the provisioner rejects the pack with nothing
/// cached.
void main() {
  SecPackDataFile file(
    String name,
    String body, {
    String version = 'CWE 4.0',
  }) => SecPackDataFile(
    name: name,
    bytes: Uint8List.fromList(utf8.encode(body)),
    upstreamVersion: version,
    licence: 'MITRE Terms of Use',
    source: 'https://cwe.mitre.org/',
  );

  // Hand-assemble a STORE-compressed zip from raw members, to craft the
  // malformed packs the happy-path builder would never produce.
  Uint8List zipOf(Map<String, List<int>> members) {
    final archive = Archive();
    members.forEach((name, bytes) {
      archive.add(
        ArchiveFile(name, bytes.length, bytes)
          ..compression = CompressionType.none,
      );
    });
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  List<int> manifestBytes(
    List<SecPackFileEntry> files, {
    int version = secPackManifestVersion,
    String packVersion = '1.0',
  }) => utf8.encode(
    jsonEncode(
      SecPackManifest(
        manifestVersion: version,
        packVersion: packVersion,
        files: files,
      ).toJson(),
    ),
  );

  SecPackFileEntry entryFor(String name, List<int> bytes) => SecPackFileEntry(
    name: name,
    sha256: secPackSha256Hex(bytes),
    version: 'v',
    licence: 'l',
    source: 's',
  );

  test('secPackSha256Hex is the lowercase hex sha256', () {
    // Well-known vector: sha256("") .
    expect(
      secPackSha256Hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('build → verify round-trips the files and manifest', () {
    final pack = buildSecPack(
      packVersion: '2025.1',
      files: [file('cwe.json', '{"a":1}'), file('capec.json', '[]')],
    );
    final contents = openAndVerifySecPack(pack);

    expect(contents.manifest.packVersion, '2025.1');
    expect(contents.manifest.manifestVersion, secPackManifestVersion);
    expect(utf8.decode(contents.files['cwe.json']!), '{"a":1}');
    expect(utf8.decode(contents.files['capec.json']!), '[]');
    // The inner MANIFEST.json is not exposed as a data file.
    expect(contents.files.containsKey(secPackManifestName), isFalse);
  });

  test('build is deterministic and sorts entries by name', () {
    final files = [file('z.json', '1'), file('a.json', '2')];
    final a = buildSecPack(packVersion: '1', files: files);
    final b = buildSecPack(packVersion: '1', files: files.reversed.toList());

    expect(a, equals(b), reason: 'same inputs → byte-identical pack');
    final names = openAndVerifySecPack(a).manifest.files.map((f) => f.name);
    expect(names, ['a.json', 'z.json']);
  });

  test('a non-zip blob is rejected', () {
    // A garbage blob is never a valid pack; whether the decoder throws or just
    // yields no manifest, the result is a rejection with nothing cached.
    expect(
      () => openAndVerifySecPack(const [1, 2, 3, 4]),
      throwsA(isA<SecPackFormatException>()),
    );
  });

  test('a missing inner manifest is rejected', () {
    final pack = zipOf({'cwe.json': utf8.encode('{}')});
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('mist'),
        ),
      ),
    );
  });

  test('an unparseable manifest is rejected', () {
    final pack = zipOf({secPackManifestName: utf8.encode('not json {')});
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('ongeldige'),
        ),
      ),
    );
  });

  test('an unknown manifest version is rejected', () {
    final pack = zipOf({
      secPackManifestName: manifestBytes(const [], version: 999),
    });
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('manifestversie'),
        ),
      ),
    );
  });

  test('a manifest entry with no matching file is rejected', () {
    final pack = zipOf({
      secPackManifestName: manifestBytes([
        entryFor('gone.json', utf8.encode('x')),
      ]),
    });
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('ontbreekt'),
        ),
      ),
    );
  });

  test('a sha256 mismatch is detected', () {
    final body = utf8.encode('real');
    final pack = zipOf({
      // Manifest claims the sha of different bytes than the file carries.
      secPackManifestName: manifestBytes([
        entryFor('cwe.json', utf8.encode('other')),
      ]),
      'cwe.json': body,
    });
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('wijkt af'),
        ),
      ),
    );
  });

  test('a file not listed in the manifest is rejected as smuggled', () {
    final pack = zipOf({
      secPackManifestName: manifestBytes(const []),
      'extra.json': utf8.encode('{}'),
    });
    expect(
      () => openAndVerifySecPack(pack),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('onverwacht lid'),
        ),
      ),
    );
  });

  test('exceeding the size cap is rejected (zip-bomb guard)', () {
    final pack = buildSecPack(packVersion: '1', files: [file('a.json', 'x')]);
    expect(
      () => openAndVerifySecPack(pack, maxBytes: 1),
      throwsA(
        isA<SecPackFormatException>().having(
          (e) => e.message,
          'message',
          contains('groottelimiet'),
        ),
      ),
    );
  });

  test('SecPackFileEntry and SecPackManifest round-trip through JSON', () {
    final manifest = SecPackManifest(
      manifestVersion: secPackManifestVersion,
      packVersion: '3',
      files: [entryFor('a.json', utf8.encode('a'))],
    );
    final decoded = SecPackManifest.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(manifest.toJson())) as Map,
      ),
    );
    expect(decoded.packVersion, '3');
    expect(decoded.files.single.name, 'a.json');
    expect(decoded.files.single.sha256, manifest.files.single.sha256);
  });

  test('SecPackFormatException stringifies with its message', () {
    expect(
      const SecPackFormatException('boom').toString(),
      'SecPackFormatException: boom',
    );
  });
}
