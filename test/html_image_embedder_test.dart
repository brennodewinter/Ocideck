import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/html_image_embedder.dart';
import 'package:ocideck/utils/image_limits.dart';

/// Een effen afbeelding van [w]×[h]. Met [alpha] krijgt de linkerhelft een
/// doorzichtige rand, zodat de test het verschil tussen "heeft een alfakanaal"
/// en "is ergens doorzichtig" kan maken.
img.Image _image(int w, int h, {bool alpha = false, bool opaqueAlpha = false}) {
  final image = img.Image(
    width: w,
    height: h,
    numChannels: alpha || opaqueAlpha ? 4 : 3,
  );
  for (final pixel in image) {
    if (alpha) {
      pixel.setRgba(0, 51, 153, pixel.x < w ~/ 2 ? 0 : 255);
    } else if (opaqueAlpha) {
      pixel.setRgba(0, 51, 153, 255);
    } else {
      pixel.setRgb(0, 51, 153);
    }
  }
  return image;
}

img.Image? _decode(Uint8List bytes) => img.decodeImage(bytes);

void main() {
  test('een te grote afbeelding wordt verkleind naar de insluitgrens', () {
    final source = Uint8List.fromList(img.encodeJpg(_image(3200, 1800)));
    final embedded = encodeForHtmlEmbed(source, 'foto.jpg');

    expect(embedded, isNotNull);
    expect(embedded!.mime, 'image/jpeg');
    final decoded = _decode(embedded.bytes)!;
    expect(decoded.width, kHtmlEmbedMaxEdge);
    // De verhouding blijft, en het bestand wordt kleiner in plaats van groter —
    // dat is de hele reden dat er niet ruw wordt ingesloten.
    expect(decoded.height, 1080);
    expect(embedded.bytes.length, lessThan(source.length));
  });

  test('een afbeelding binnen de grens wordt niet opgerekt', () {
    final source = Uint8List.fromList(img.encodeJpg(_image(800, 600)));
    final embedded = encodeForHtmlEmbed(source, 'klein.jpg')!;

    final decoded = _decode(embedded.bytes)!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
  });

  test('doorzichtigheid blijft: dan PNG en geen JPEG', () {
    final source = Uint8List.fromList(
      img.encodePng(_image(200, 100, alpha: true)),
    );
    final embedded = encodeForHtmlEmbed(source, 'logo.png')!;

    expect(embedded.mime, 'image/png');
    final decoded = _decode(embedded.bytes)!;
    expect(decoded.getPixel(10, 10).a, 0, reason: 'de doorzichtige helft');
  });

  test('een alfakanaal zonder doorzichtige pixel wordt gewoon JPEG', () {
    // Een schermafdruk in PNG draagt vrijwel altijd een ongebruikt alfakanaal.
    // Daarop afgaan zou elke schermafdruk als PNG insluiten — vele malen groter
    // dan nodig, in precies het formaat dat een rapport het meest gebruikt.
    final source = Uint8List.fromList(
      img.encodePng(_image(400, 300, opaqueAlpha: true)),
    );
    final embedded = encodeForHtmlEmbed(source, 'schermafdruk.png')!;

    expect(embedded.mime, 'image/jpeg');
  });

  test('SVG en GIF gaan ongewijzigd mee', () {
    final svg = Uint8List.fromList(
      utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
    );
    final embeddedSvg = encodeForHtmlEmbed(svg, 'schema.svg')!;
    expect(embeddedSvg.mime, 'image/svg+xml');
    expect(embeddedSvg.bytes, svg);

    final gif = Uint8List.fromList(img.encodeGif(_image(40, 40)));
    final embeddedGif = encodeForHtmlEmbed(gif, 'animatie.GIF')!;
    // Hoofdletters in de extensie tellen ook; en opnieuw coderen zou de
    // beweging uit een GIF halen.
    expect(embeddedGif.mime, 'image/gif');
    expect(embeddedGif.bytes, gif);
  });

  test('een GIF met een reusachtig canvas wordt niet ingesloten (#1044)', () {
    // Een geldig, maar minuscuul GIF-bestand kan een logisch scherm van
    // 30000×30000 declareren. Voorheen ging een GIF ongewijzigd mee vóór de
    // dimensieprobe, zodat dit de decodeerbomgrens omzeilde en de ontvanger bij
    // het openen gigabytes per frame kostte.
    const w = 30000; // 0x7530
    final oversized = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
      w & 0xff, (w >> 8) & 0xff, // logische breedte, little-endian
      w & 0xff, (w >> 8) & 0xff, // logische hoogte, little-endian
      0x00, 0x00, 0x00, // packed (geen GCT), achtergrond, aspect
    ]);
    // De probe moet het gedeclareerde canvas zien, niet de bestandsgrootte.
    expect(oversized.length, lessThan(64));
    expect(encodeForHtmlEmbed(oversized, 'bom.gif'), isNull);
  });

  test('de EXIF van een foto reist niet mee naar de ontvanger', () {
    // Ruwe cameravorm insluiten zou de GPS-locatie, het tijdstip en het
    // serienummer van het toestel meesturen naar iedereen die het rapport
    // krijgt — in een document dat juist over andermans beveiliging gaat.
    final photo = _image(600, 400);
    photo.exif.imageIfd['Model'] = 'OciDeckCam 9000';
    final source = Uint8List.fromList(img.encodeJpg(photo));
    expect(
      String.fromCharCodes(source),
      contains('OciDeckCam'),
      reason: 'de bron draagt de EXIF wél',
    );

    final embedded = encodeForHtmlEmbed(source, 'foto.jpg')!;
    expect(String.fromCharCodes(embedded.bytes), isNot(contains('OciDeckCam')));
  });

  test('een decodeerbom wordt niet ingesloten', () {
    // Een effen PNG van 8000×8000 is klein op schijf en honderden megabytes
    // uitgepakt; hier is niets te redden, want verkleinen kan pas ná decoderen.
    final source = Uint8List.fromList(
      img.encodePng(_image(kMaxImageDecodeDimension + 100, 8)),
    );
    expect(encodeForHtmlEmbed(source, 'bom.png'), isNull);
  });

  test('onleesbare of lege bytes leveren niets op', () {
    expect(encodeForHtmlEmbed(Uint8List(0), 'leeg.png'), isNull);
    expect(
      encodeForHtmlEmbed(Uint8List.fromList([1, 2, 3, 4]), 'stuk.png'),
      isNull,
    );
  });

  test('de data-URI draagt het juiste mediatype', () {
    final uri = htmlImageDataUri((
      mime: 'image/jpeg',
      bytes: Uint8List.fromList([1, 2, 3]),
    ));
    expect(uri, startsWith('data:image/jpeg;base64,'));
    expect(uri, endsWith(base64Encode([1, 2, 3])));
  });
}
