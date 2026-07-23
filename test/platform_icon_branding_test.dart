import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// De app-iconen van Linux en Windows bleven bij de rebrand achter. Toen het
/// merk in juni van de fotokat naar de lijntekening ging (`da7b7c9e`,
/// `dc62e03f`, `c6ccd42c`), zijn alleen de macOS-set en de webiconen opnieuw
/// gegenereerd. `linux/runner/resources/app_icon.png` en
/// `windows/runner/resources/app_icon.ico` bleven staan op wat `20906ddb` er in
/// juni had neergezet, en die twee zijn wel degelijk ondersteunde bouwdoelen:
/// wie `make build-linux` of `make build-windows` draaide, kreeg een app met de
/// oude huisstijl in de taakbalk.
///
/// Geen enkele poort zag dat. Iconen zijn geen Dart, staan niet in
/// `pubspec.yaml` en worden door de runner via een pad opgepikt — er is niets
/// dat rood wordt als er een achterblijft. Daarom toetst dit bestand de
/// *bestanden*: draagt elk bureaubladdoel dezelfde tekening als het merk. Dat
/// is de vraag die bij de volgende rebrand opnieuw gesteld moet worden, en de
/// enige die deze fout had gevangen.
void main() {
  img.Image lees(String pad) {
    final bestand = File(pad);
    expect(bestand.existsSync(), isTrue, reason: '$pad ontbreekt');
    final bytes = bestand.readAsBytesSync();
    final decoded = pad.endsWith('.ico')
        ? img.decodeIco(bytes)
        : img.decodePng(bytes);
    expect(decoded, isNotNull, reason: '$pad is niet te decoderen');
    return decoded!;
  }

  /// Een grove grijswaarde-vingerafdruk van de tékening: bijsnijden tot de
  /// inhoud, dan platslaan naar 32x32. Zo valt het verschil in canvasgrootte en
  /// marge weg en blijft over waar het om gaat — welke kat er staat.
  img.Image vingerafdruk(img.Image bron) => img.grayscale(
    img.copyResize(
      img.trim(bron, mode: img.TrimMode.topLeftColor),
      width: 32,
      height: 32,
      maintainAspect: false,
    ),
  );

  double afstand(img.Image a, img.Image b) {
    var som = 0.0;
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        som +=
            (a.getPixel(x, y).luminanceNormalized -
                    b.getPixel(x, y).luminanceNormalized)
                .abs();
      }
    }
    return som / (32 * 32);
  }

  /// Aandeel ondoorzichtige pixels met een uitgesproken kleur. De lijntekening
  /// is neutrale inkt op wit en komt op nul uit; de fotokat — gele poten, rode
  /// halsband — zat boven de vijftig procent.
  double kleuraandeel(img.Image beeld) {
    var ondoorzichtig = 0;
    var gekleurd = 0;
    for (var y = 0; y < beeld.height; y++) {
      for (var x = 0; x < beeld.width; x++) {
        final p = beeld.getPixel(x, y);
        if (p.a < 200) continue;
        ondoorzichtig++;
        final hoog = math.max(p.r, math.max(p.g, p.b));
        final laag = math.min(p.r, math.min(p.g, p.b));
        if (hoog - laag > 40) gekleurd++;
      }
    }
    expect(
      ondoorzichtig,
      greaterThan(0),
      reason: 'icoon is volledig doorzichtig',
    );
    return gekleurd / ondoorzichtig;
  }

  const merkpad = 'assets/images/ocideck-logo.png';

  /// Het grootste kunstwerk per bouwdoel. Bewust niet de kleine formaten: bij
  /// 16 of 64 pixels waaieren de dunne lijnen zo ver uit dat de vingerafdruk
  /// vanzelf richting 0,19 loopt — dat is verschaling, geen huisstijl. De
  /// kleine maten worden hieronder wél op kleur getoetst.
  const grootste = {
    'macOS':
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    'Linux': 'linux/runner/resources/app_icon.png',
    'Windows': 'windows/runner/resources/app_icon.ico',
    'web': 'web/icons/Icon-512.png',
  };

  /// De maten waarin de macOS-set is uitgeschreven.
  const macosMaten = [16, 32, 64, 128, 256, 512, 1024];

  test('elk bureaubladdoel toont dezelfde tekening als het merk', () {
    final merk = vingerafdruk(lees(merkpad));
    for (final MapEntry(key: doel, value: pad) in grootste.entries) {
      final beeld = lees(pad);
      // Een .ico draagt meerdere formaten; pak het grootste.
      final kunstwerk = beeld.frames.reduce(
        (a, b) => b.width > a.width ? b : a,
      );
      expect(
        afstand(merk, vingerafdruk(kunstwerk)),
        lessThan(0.20),
        reason:
            '$doel ($pad) toont een andere tekening dan $merkpad — precies zoals '
            'Linux en Windows de fotokat bleven dragen nadat het merk was '
            'veranderd. Genereer het icoon opnieuw uit het merk.',
      );
    }
  });

  test('geen enkel icoonformaat draagt de verzadigde kleur van de foto', () {
    final paden = [
      ...grootste.values,
      for (final n in macosMaten)
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$n.png',
      'web/favicon.png',
      'web/icons/Icon-192.png',
    ].where((pad) => File(pad).existsSync());

    for (final pad in paden) {
      for (final formaat in lees(pad).frames) {
        expect(
          kleuraandeel(formaat),
          lessThan(0.01),
          reason:
              '$pad (${formaat.width}px) staat vol verzadigde kleur; de '
              'huisstijl is neutrale inkt op wit',
        );
      }
    }
  });

  test('het Windows-icoon draagt nog steeds al zijn formaten', () {
    // Eén 256-pixelplaatje in een .ico laat Windows zelf verkleinen, en dat
    // ziet er in de taakbalk slechter uit dan een eigen 16 en 24.
    final maten = lees(
      'windows/runner/resources/app_icon.ico',
    ).frames.map((f) => f.width).toList()..sort();
    expect(maten, [16, 24, 32, 48, 64, 128, 256]);
  });
}
