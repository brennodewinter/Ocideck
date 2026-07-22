// Een sidecar reist mee met een deck — uit een pakket, een repo, of een map die
// iemand anders heeft gemaakt. Zonder grens leest een gemanipuleerd bestand van
// een gigabyte zich zo het geheugen in, en `jsonDecode` legt er nog een kopie
// bovenop.
//
// De schrijfkant is de scherpste: boven de grens mag `write` niet doorgaan met
// een lege map, want die zou over het bestand heen gaan en alle andere
// bijschriften in die map wissen. Precies de fout die het bestaande catch-blok
// beschrijft, alleen met een andere aanleiding.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/image_sidecar_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sidecar_cap'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Een sidecar met één echte entry, opgeblazen tot boven de grens met een
  /// tweede sleutel. Geldige JSON — het gaat om de omvang, niet om corruptie.
  File tooLarge(ImageSidecarStore store, String dir) {
    final file = File(p.join(dir, store.sidecarName));
    file.writeAsStringSync(
      jsonEncode({
        'foto.png': 'echt bijschrift',
        'opvulling': 'x' * (maxImageSidecarBytes + 1024),
      }),
    );
    return file;
  }

  final store = ImageSidecarStore(
    sidecarName: '.ocideck-captions.json',
    logLabel: 'TestSidecar',
  );

  test('een sidecar boven de grens wordt niet gelezen', () async {
    tooLarge(store, tmp.path);
    final value = await store.read(p.join(tmp.path, 'foto.png'));
    expect(
      value,
      isNull,
      reason: 'boven de grens hoort er niets terug te komen',
    );
    expect(await store.readDir(tmp.path), isEmpty);
  });

  test('schrijven laat een te grote sidecar ongemoeid', () async {
    final file = tooLarge(store, tmp.path);
    final before = file.readAsStringSync();

    await store.write(p.join(tmp.path, 'nieuw.png'), 'nieuw bijschrift');

    expect(
      file.readAsStringSync(),
      before,
      reason:
          'doorgaan met een lege map zou het bestand overschrijven en alle '
          'andere bijschriften in deze map wissen',
    );
  });

  test('een normale sidecar werkt gewoon', () async {
    await store.write(p.join(tmp.path, 'foto.png'), 'een bijschrift');
    expect(await store.read(p.join(tmp.path, 'foto.png')), 'een bijschrift');
    expect(await store.readDir(tmp.path), {'foto.png': 'een bijschrift'});
  });
}
