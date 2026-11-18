@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/pack_web_release.dart';

void main() {
  test(
    'incremental packaging refreshes release metadata without a checksum cycle',
    () {
      final root = Directory.systemTemp.createTempSync('ocideck-precache-');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final file in [...releaseArtefacten.values, 'build-info.json']) {
        final target = File('${root.path}/$file');
        target.parent.createSync(recursive: true);
        target.writeAsStringSync('new $file');
      }
      final manifest = File('${root.path}/precache_manifest.json');
      manifest.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'entries': [
            {'url': 'SHA256SUMS', 'hash': 'old', 'urlHashed': false},
            {'url': 'sbom/ocideck.cdx.json', 'hash': 'old', 'urlHashed': false},
            {
              'url': 'main.dart.12345678.wasm',
              'hash': '12345678',
              'urlHashed': true,
            },
          ],
        }),
      );
      normaliseerPrecacheManifest(root);
      final result =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      final entries = (result['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(entries.any((e) => e['url'] == 'SHA256SUMS'), isFalse);
      final sbom = entries.singleWhere(
        (e) => e['url'] == 'sbom/ocideck.cdx.json',
      );
      expect(
        sbom['hash'],
        sha256
            .convert(utf8.encode('new sbom/ocideck.cdx.json'))
            .toString()
            .substring(0, 8),
      );
      expect(
        entries.singleWhere((e) => e['urlHashed'] == true)['hash'],
        '12345678',
      );
      final first = manifest.readAsStringSync();
      normaliseerPrecacheManifest(root);
      expect(manifest.readAsStringSync(), first);
    },
  );
}
