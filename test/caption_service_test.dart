import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final service = CaptionService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_cap'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saves and reads back a caption via the sidecar file', () async {
    final img = p.join(tmp.path, 'photo.png');
    await service.saveCaption(img, 'Een onderschrift');
    expect(await service.getCaption(img), 'Een onderschrift');
  });

  test('returns null when there is no caption', () async {
    expect(await service.getCaption(p.join(tmp.path, 'none.png')), isNull);
  });

  test('saving an empty caption removes it', () async {
    final img = p.join(tmp.path, 'photo.png');
    await service.saveCaption(img, 'Tekst');
    await service.saveCaption(img, '   ');
    expect(await service.getCaption(img), isNull);
  });

  test('captions are stored per image basename', () async {
    final a = p.join(tmp.path, 'a.png');
    final b = p.join(tmp.path, 'b.png');
    await service.saveCaption(a, 'Onderschrift A');
    await service.saveCaption(b, 'Onderschrift B');
    expect(await service.getCaption(a), 'Onderschrift A');
    expect(await service.getCaption(b), 'Onderschrift B');
  });

  test('copyCaption duplicates a caption to another image', () async {
    final a = p.join(tmp.path, 'a.png');
    final b = p.join(tmp.path, 'b.png');
    await service.saveCaption(a, 'Gedeeld');
    await service.copyCaption(a, b);
    expect(await service.getCaption(b), 'Gedeeld');
  });
}
