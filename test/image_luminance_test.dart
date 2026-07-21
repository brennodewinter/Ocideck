import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/utils/image_luminance.dart';
import 'package:path/path.dart' as p;

/// De gemiddelde kleur van een afbeelding. Hierop schat de kwaliteitscontrole
/// waar de titeltekst van een titelslide op komt te staan, dus een verkeerd
/// gemiddelde levert een verkeerd contrastoordeel — en dat is precies het
/// oordeel waarop een gebruiker vertrouwt om leesbaar te blijven.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_luminance_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Schrijft [image] als PNG en geeft het pad terug.
  Future<String> write(img.Image image, {String name = 'a.png'}) async {
    final path = p.join(temp.path, name);
    await File(path).writeAsBytes(img.encodePng(image));
    return path;
  }

  img.Image filled(int r, int g, int b, {int a = 255, int size = 64}) {
    final image = img.Image(width: size, height: size, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(r, g, b, a));
    return image;
  }

  /// Kleurkanalen wijken bij het verkleinen naar 48×48 een paar punten af; het
  /// gaat om de kleur, niet om de laatste bit.
  void expectNear(Color? actual, Color expected, {int tolerance = 12}) {
    expect(actual, isNotNull);
    for (final channel in const ['r', 'g', 'b']) {
      final a = switch (channel) {
        'r' => actual!.r,
        'g' => actual!.g,
        _ => actual!.b,
      };
      final e = switch (channel) {
        'r' => expected.r,
        'g' => expected.g,
        _ => expected.b,
      };
      expect(
        (a * 255 - e * 255).abs(),
        lessThanOrEqualTo(tolerance.toDouble()),
        reason: '$channel: $actual week te ver af van $expected',
      );
    }
  }

  test('een egale afbeelding levert precies die kleur', () async {
    final path = await write(filled(200, 30, 40));

    expectNear(await averageImageColor(path), const Color(0xFFC81E28));
  });

  test('twee helften leveren het gemiddelde, niet één van beide', () async {
    final image = filled(255, 0, 0);
    img.fillRect(
      image,
      x1: 32,
      y1: 0,
      x2: 63,
      y2: 63,
      color: img.ColorRgba8(0, 0, 255, 255),
    );
    final path = await write(image);

    // Halverwege rood en blauw.
    expectNear(await averageImageColor(path), const Color(0xFF800080));
  });

  test('doorzichtige pixels trekken het gemiddelde niet naar zwart', () async {
    // Een uitgesneden logo: de helft is volledig doorzichtig. Tellen we die
    // mee, dan komt er donkerrood uit en oordeelt de contrastcontrole dat
    // witte tekst er wel op kan.
    final image = filled(255, 0, 0);
    // Pixel voor pixel, niet met fillRect: die mengt, en een volledig
    // doorzichtige kleus erover mengen laat het rood gewoon staan — dan toetst
    // deze test niets.
    for (var y = 0; y < 64; y++) {
      for (var x = 32; x < 64; x++) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final path = await write(image);

    expectNear(
      await averageImageColor(path),
      const Color(0xFFFF0000),
      tolerance: 20,
    );
  });

  test('halfdoorzichtig rood is rood, niet donkerrood', () async {
    // rawRgba is premultiplied; zonder terugrekenen komt hier ~#800000 uit.
    final path = await write(filled(255, 0, 0, a: 128));

    expectNear(
      await averageImageColor(path),
      const Color(0xFFFF0000),
      tolerance: 20,
    );
  });

  test('een volledig doorzichtige afbeelding valt terug op zwart', () async {
    final path = await write(filled(255, 255, 255, a: 0));

    expect(await averageImageColor(path), Colors.black);
  });

  test('een bestand dat er niet is levert niets op', () async {
    expect(await averageImageColor(p.join(temp.path, 'weg.png')), isNull);
  });

  test('onleesbare bytes leveren niets op, geen uitzondering', () async {
    final path = p.join(temp.path, 'kapot.png');
    await File(path).writeAsBytes(List.filled(64, 0x41));

    expect(await averageImageColor(path), isNull);
  });

  test('een gewijzigd bestand levert de nieuwe kleur, niet de oude', () async {
    final path = await write(filled(255, 0, 0));
    expectNear(await averageImageColor(path), const Color(0xFFFF0000));

    // Overschrijven met een andere kleur én een andere lengte: de cache moet
    // dat merken, anders blijft de kwaliteitscontrole op de oude achtergrond
    // oordelen zolang de app open staat.
    await File(path).writeAsBytes(img.encodePng(filled(0, 0, 255, size: 96)));
    expectNear(await averageImageColor(path), const Color(0xFF0000FF));
  });

  test('een tweede lezing van hetzelfde bestand geeft hetzelfde', () async {
    final path = await write(filled(10, 120, 200));

    final first = await averageImageColor(path);
    final second = await averageImageColor(path);
    expect(second, first);
  });
}
