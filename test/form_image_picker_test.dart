// De bestandskiezer en de map van het document als wat de invulpagina voor foto's
// nodig heeft (FormImageSupport).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/widgets/forms/form_image_picker.dart';
import 'package:path/path.dart' as p;

Uint8List photo() {
  final image = img.Image(width: 30, height: 20);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return img.encodeJpg(image);
}

FormImagePick file(String name, Uint8List bytes) =>
    (name: name, read: () async => bytes);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_formpick_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('zonder projectmap is er geen ondersteuning', () {
    expect(formImageSupportFor(projectPath: null, dialogTitle: 'Kies'), isNull);
  });

  test('de kiezer biedt foto\'s aan, geen alles', () {
    expect(kFormImageExtensions, containsAll(['jpg', 'png', 'webp', 'heic']));
    expect(kFormImageExtensions, isNot(contains('svg')));
    expect(kFormImageExtensions, isNot(contains('gif')));
  });

  test('een keuze wordt verwerkt; wat geen foto is wordt geweigerd', () async {
    String? seenTitle;
    final support = formImageSupportFor(
      projectPath: dir.path,
      dialogTitle: 'Kies een afbeelding',
      pick: (title) async {
        seenTitle = title;
        return [
          file('IMG_0001.JPG', photo()),
          file('notities.jpg', Uint8List.fromList('geen foto'.codeUnits)),
        ];
      },
    )!;
    final batch = await support.add('foto', {});
    expect(seenTitle, 'Kies een afbeelding');
    expect(batch!.stored.map((s) => s.path), ['images/foto-1.jpg']);
    expect(batch.refused, hasLength(1));
    // De bestandsnaam van de invuller komt nergens terug.
    expect(
      Directory(
        p.join(dir.path, 'images'),
      ).listSync().map((e) => p.basename(e.path)),
      ['foto-1.jpg'],
    );
  });

  test('annuleren geeft null', () async {
    final support = formImageSupportFor(
      projectPath: dir.path,
      dialogTitle: 'Kies',
      pick: (_) async => [],
    )!;
    expect(await support.add('foto', {}), isNull);
  });

  test('meten gaat naar de projectmap', () async {
    await Directory(p.join(dir.path, 'images')).create();
    await File(p.join(dir.path, 'images', 'a-1.jpg')).writeAsBytes(photo());
    final support = formImageSupportFor(
      projectPath: dir.path,
      dialogTitle: 'Kies',
      pick: (_) async => [],
    )!;
    final facts = await support.probe(['images/a-1.jpg']);
    expect(facts['images/a-1.jpg']!.displayedWidth, 30);
  });

  test('een voorbeeld bestaat alleen voor een pad binnen de projectmap', () {
    final support = formImageSupportFor(
      projectPath: dir.path,
      dialogTitle: 'Kies',
      pick: (_) async => [],
    )!;
    final inside = support.preview('images/a-1.jpg');
    expect(inside, isA<FileImage>());
    expect(
      (inside as FileImage).file.path,
      p.join(dir.path, 'images', 'a-1.jpg'),
    );
    expect(support.preview('../buiten.jpg'), isNull);
    expect(support.preview(''), isNull);
  });
}
