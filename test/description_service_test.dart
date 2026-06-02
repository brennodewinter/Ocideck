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
