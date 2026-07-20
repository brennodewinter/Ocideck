import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/image_sidecar_store.dart';

/// Paden waar een fout of een rare byte stilzwijgend werk kostte.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ocideck_loss_test');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('bijschrift-sidecar', () {
    const store = ImageSidecarStore(
      sidecarName: '.captions.json',
      logLabel: 'test',
    );

    File sidecar() => File('${dir.path}/.captions.json');

    test('een beschadigde sidecar wordt niet overschreven', () async {
      // Eén kapot bestand — een synchronisatieconflict, een halve kopie — kostte
      // álle andere bijschriften in die map: de parse mislukte, de code ging
      // door met een lege map, en schreef die eroverheen.
      sidecar().writeAsStringSync('{dit is geen json');

      await expectLater(
        store.write('${dir.path}/foto.png', 'nieuw bijschrift'),
        throwsA(isA<SidecarUnreadable>()),
      );
      expect(
        sidecar().readAsStringSync(),
        '{dit is geen json',
        reason: 'het bestand blijft onaangeroerd',
      );
    });

    test('een beschadigde sidecar wordt ook niet verwijderd', () async {
      // De variant die er nog erger uitzag: bij het wíssen van een bijschrift
      // bleef de map leeg en werd het hele bestand weggegooid.
      sidecar().writeAsStringSync('{dit is geen json');

      await expectLater(
        store.write('${dir.path}/foto.png', ''),
        throwsA(isA<SidecarUnreadable>()),
      );
      expect(sidecar().existsSync(), isTrue);
    });

    test('een gezonde sidecar blijft gewoon werken', () async {
      await store.write('${dir.path}/een.png', 'eerste');
      await store.write('${dir.path}/twee.png', 'tweede');

      final data = jsonDecode(sidecar().readAsStringSync()) as Map;
      expect(data['een.png'], 'eerste');
      expect(data['twee.png'], 'tweede');

      // En wissen laat de rest staan.
      await store.write('${dir.path}/een.png', '');
      final after = jsonDecode(sidecar().readAsStringSync()) as Map;
      expect(after.containsKey('een.png'), isFalse);
      expect(after['twee.png'], 'tweede');
    });
  });
}
