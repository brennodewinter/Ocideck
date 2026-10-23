// De WASM-artifacten in `web/whisper/` (#2513): `libmain.js`/`libmain.wasm`
// zijn gebouwd uit gepinde whisper.cpp-bron via een vaste toolchain, en
// `bridge.js` is de eigen dunne laag. `manifest.json` pint de hashes van de
// gegenereerde stukken — een artifact dat verandert zonder het manifest (en
// dus zonder herbouw uit de gepinde bron) is geen build meer maar een
// hand-edit, en die hoort rood te slaan.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifestFile = File('web/whisper/manifest.json');

  test('het manifest bestaat en noemt herkomst en toolchain', () {
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['upstream'], 'whisper.cpp');
    expect(manifest['upstreamVersion'], isA<String>());
    expect(manifest['upstreamLicense'], 'MIT');
    expect(manifest['toolchain'], isNotNull);
    // De build verschilt van upstream (cancel-binding) — het patchbestand
    // dat dat verklaart moet bestaan, anders is de herkomst onverifieerbaar.
    expect(
      File('${manifest['patch']}').existsSync(),
      isTrue,
      reason: 'het emscripten-patchbestand hoort gecommit te zijn',
    );
  });

  test('elke gepinde hash klopt met het artifact op disk', () {
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final files = manifest['files'] as Map<String, dynamic>;
    expect(files, isNotEmpty);
    for (final entry in files.entries) {
      final f = File('web/whisper/${entry.key}');
      expect(f.existsSync(), isTrue, reason: '${entry.key} ontbreekt');
      final actual = sha256.convert(f.readAsBytesSync()).toString();
      expect(
        actual,
        entry.value['sha256'],
        reason:
            '${entry.key} week af van het manifest — herbouw uit de gepinde '
            'bron en werk manifest.json bij, in plaats van het artifact te '
            'editen',
      );
    }
  });

  test('de wasm vraagt pthreads — cross-origin isolatie is dus vereist', () {
    // Het `requires`-blok is de contractzijde van de .htaccess-headers: wie
    // COOP/COEP verwijdert krijgt geen SharedArrayBuffer en de engine meldt
    // noIsolation. De test hier is de bronkant van die belofte.
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final requires = manifest['requires'] as Map<String, dynamic>;
    expect(requires['crossOriginIsolation'], isTrue);
    expect(requires['sharedArrayBuffer'], isTrue);
  });
}
