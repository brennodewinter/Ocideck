import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final service = DescriptionService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_desc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saves and reads back a description', () async {
    final img = p.join(tmp.path, 'photo.png');
    await service.saveDescription(img, 'Zonsondergang aan zee');
    expect(await service.getDescription(img), 'Zonsondergang aan zee');
  });

  test('returns null when there is no description', () async {
    expect(await service.getDescription(p.join(tmp.path, 'none.png')), isNull);
  });

  test('removing a description deletes the entry', () async {
    final img = p.join(tmp.path, 'photo.png');
    await service.saveDescription(img, 'Tekst');
    await service.removeDescription(img);
    expect(await service.getDescription(img), isNull);
  });

  test('copyDescription neemt de tags mee naar de kopie (#2147)', () async {
    final source = p.join(tmp.path, 'bron.png');
    final destDir = Directory(p.join(tmp.path, 'project', 'images'))
      ..createSync(recursive: true);
    final dest = p.join(destDir.path, 'bron.png');
    await service.saveDescription(source, 'zon, zee');

    await service.copyDescription(source, dest);

    expect(await service.getDescription(dest), 'zon, zee');
    // Het is een kopie: de bron behoudt zijn eigen beschrijving.
    expect(await service.getDescription(source), 'zon, zee');
  });

  test(
    'copyDescription voegt samen in plaats van te overschrijven (#2147)',
    () async {
      final source = p.join(tmp.path, 'bron.png');
      final dest = p.join(tmp.path, 'hergebruikt.png');
      await service.saveDescription(source, 'zon');
      await service.saveDescription(dest, 'handmatige tag');

      await service.copyDescription(source, dest);

      final merged = await service.getDescription(dest);
      expect(merged, contains('handmatige tag'));
      expect(merged, contains('zon'));
    },
  );

  test('copyDescription doet niets zonder bronbeschrijving (#2147)', () async {
    final dest = p.join(tmp.path, 'dest.png');
    await service.saveDescription(dest, 'blijft');

    await service.copyDescription(p.join(tmp.path, 'geen.png'), dest);

    expect(await service.getDescription(dest), 'blijft');
  });

  test(
    'loadFor returns all descriptions in the relevant directories',
    () async {
      final a = p.join(tmp.path, 'a.png');
      final b = p.join(tmp.path, 'b.png');
      await service.saveDescription(a, 'Berg');
      await service.saveDescription(b, 'Rivier');

      final all = await service.loadFor([a, b, p.join(tmp.path, 'c.png')]);
      expect(all[a], 'Berg');
      expect(all[b], 'Rivier');
      expect(all.containsKey(p.join(tmp.path, 'c.png')), isFalse);
    },
  );
}
