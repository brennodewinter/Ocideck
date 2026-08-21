// Toetst de belofte die de export na afloop dóét over het logo.
//
// De interface zegt tegen de gebruiker: dit bestand is zóveel beeldpunten, komt
// op deze maat uit op zóveel dpi, neem er een van minstens zóveel breed. Dat
// zijn drie getallen die kloppen moeten — een waarschuwing met een verzonnen
// advies is erger dan geen waarschuwing, want de gebruiker gaat er een bestand
// op aanschaffen.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';

void main() {
  /// Een 4×2 PNG. Klein en breed, precies de vorm van een beeldmerk.
  final wide = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGP4z8AARwzIHABv'
      'qgf5gNwAKAAAAABJRU5ErkJggg==',
    ),
  );

  test('leest de beeldmaat uit het bestand zelf', () {
    final logo = logoResolutionOf(wide, boxSide: 72);
    expect(logo, isNotNull);
    expect(logo!.pixelWidth, 4);
    expect(logo.pixelHeight, 2);
  });

  test('rekent de fijnheid op de plek waar het logo terechtkomt', () {
    // Breed beeld in een vierkant kader: de breedte raakt het kader het eerst,
    // dus 4 px wordt 72 pt oftewel één duim — 4 dpi.
    expect(logoResolutionOf(wide, boxSide: 72)!.dpi, closeTo(4, 0.01));
    // Half zo groot geplaatst is twee keer zo fijn.
    expect(logoResolutionOf(wide, boxSide: 36)!.dpi, closeTo(8, 0.01));
  });

  test('een logo dat te grof is voor drukwerk wordt als zodanig gemeld', () {
    expect(logoResolutionOf(wide, boxSide: 72)!.isCoarse, isTrue);
  });

  test('een logo dat fijn genoeg is klaagt niet', () {
    // 4 px op 1 pt breed is 288 dpi — ruim boven de drukondergrens.
    final logo = logoResolutionOf(wide, boxSide: 1);
    expect(logo!.dpi, greaterThan(LogoResolution.printFloor));
    expect(logo.isCoarse, isFalse);
  });

  test('het advies is de maat waarop het logo wél fijn genoeg zou zijn', () {
    final logo = logoResolutionOf(wide, boxSide: 72)!;
    // Van 4 dpi naar de ondergrens van 150 is ruim zevenendertig keer zoveel
    // beeld: 4 × 150 / 4 = 150 beeldpunten breed.
    expect(logo.advisedPixelWidth, 150);
    // En op die maat zou de melding niet meer afgaan.
    final advised = logo.pixelWidth * LogoResolution.printFloor / logo.dpi;
    expect(
      advised / (72 / 72),
      greaterThanOrEqualTo(LogoResolution.printFloor),
    );
  });

  test('zonder logo valt er niets te melden', () {
    expect(logoResolutionOf(null, boxSide: 72), isNull);
    expect(logoResolutionOf(Uint8List(0), boxSide: 72), isNull);
  });

  test('bytes die geen afbeelding zijn leveren geen melding op', () {
    // Een SVG komt hier langs de resolver binnen; de rasterlezer maakt er niets
    // van. Dat mag geen uitzondering worden die de export meesleurt.
    final svg = Uint8List.fromList(utf8.encode('<svg xmlns="x"></svg>'));
    expect(logoResolutionOf(svg, boxSide: 72), isNull);
  });
}
