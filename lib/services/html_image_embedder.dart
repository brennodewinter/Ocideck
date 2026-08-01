import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../utils/image_limits.dart';
import '../utils/log.dart';

/// De langste zijde waarop een afbeelding het HTML-document in gaat.
///
/// De export belooft één bestand dat offline opent. Dat kan alleen als het beeld
/// erin zit, en base64 kost daar nog een derde bovenop. Een foto van 4000 pixels
/// breed uit een telefoon is 4 MB op schijf en 5,5 MB in het document, terwijl
/// een dia 1280 pixels breed is: alles boven deze grens is beeld dat niemand
/// ooit ziet en dat de ontvanger wél moet downloaden.
///
/// 1920 is bewust ruimer dan de dia zelf, zodat inzoomen op een schermafdruk van
/// een bevinding scherp blijft — precies wat een pentestrapport nodig heeft.
const int kHtmlEmbedMaxEdge = 1920;

/// De JPEG-kwaliteit voor het insluiten. Hoog genoeg dat een schermafdruk met
/// tekst leesbaar blijft, laag genoeg dat een foto niet megabytes kost.
const int kHtmlEmbedJpegQuality = 82;

/// Wat er van een afbeelding het document in gaat.
typedef HtmlEmbeddedImage = ({String mime, Uint8List bytes});

/// De extensies die ONGEWIJZIGD meegaan, met hun mediatype.
///
/// SVG is tekst en heeft geen pixels om te verkleinen. Een GIF gaat óók
/// ongewijzigd mee (opnieuw coderen zou de beweging wissen), maar niet
/// onvoorwaardelijk: die loopt eerst langs een dimensiecontrole, zie
/// [_embedGifIfBounded]. Een klein GIF-bestand kan een enorm logisch scherm
/// declareren (30000×30000) en zou anders de decode-bomgrens omzeilen (#1044).
const _passThrough = {'.svg': 'image/svg+xml'};

/// Zet de bytes van een afbeelding om in de vorm waarin ze het document in gaat,
/// of geeft null wanneer er niets bruikbaars in zit.
///
/// Een zuivere functie zonder I/O, zodat de aanroeper hem in een isolate kan
/// draaien: decoderen en opnieuw coderen kost honderden milliseconden per
/// afbeelding, en dat mag de interface niet laten staan tijdens een export.
///
/// Drie dingen gebeuren hier, en alle drie met opzet:
///
/// 1. **Begrenzen.** Een afbeelding boven [kMaxImageDecodeDimension] wordt niet
///    eens gedecodeerd — een egaal gekleurde PNG van 30000×30000 is een paar KB
///    op schijf en gigabytes uitgepakt.
/// 2. **Verkleinen.** Alles boven [kHtmlEmbedMaxEdge] gaat terug naar die maat.
/// 3. **Opnieuw coderen.** JPEG, tenzij de afbeelding écht doorzichtige pixels
///    heeft — dan PNG, want een logo op een gekleurde achtergrond mag geen witte
///    doos worden.
///
/// Het opnieuw coderen heeft een tweede opbrengst die hier niet bijzaak is: het
/// gooit de EXIF weg. Ruwe cameravorm insluiten zou de GPS-locatie, het tijdstip
/// en het serienummer van het toestel meesturen naar iedereen die het rapport
/// krijgt — in een document dat juist over andermans beveiliging gaat.
HtmlEmbeddedImage? encodeForHtmlEmbed(Uint8List bytes, String source) {
  if (bytes.isEmpty) return null;
  final passThrough = _passThroughFor(source);
  if (passThrough != null) return (mime: passThrough, bytes: bytes);

  // A GIF is kept as-is to preserve its animation, but only once its declared
  // canvas is known to be within the decode cap — the SVG-style unconditional
  // pass-through above skipped that check and let an oversized GIF through
  // (#1044).
  if (_looksLikeGif(bytes)) return _embedGifIfBounded(bytes, source);

  try {
    final probe = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (probe != null &&
        (probe.width > kMaxImageDecodeDimension ||
            probe.height > kMaxImageDecodeDimension)) {
      // Zie kMaxImageDecodeDimension: dit is de decodeerbom-grens, niet een
      // smaakoordeel over grootte. Verkleinen kan pas ná het decoderen, dus hier
      // is er niets te redden.
      logWarning(
        'encodeForHtmlEmbed: image exceeds the decode cap, not embedded',
        source,
      );
      return null;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width >= decoded.height
        ? decoded.width
        : decoded.height;
    final scaled = longest <= kHtmlEmbedMaxEdge
        ? decoded
        : (decoded.width >= decoded.height
              ? img.copyResize(
                  decoded,
                  width: kHtmlEmbedMaxEdge,
                  interpolation: img.Interpolation.average,
                )
              : img.copyResize(
                  decoded,
                  height: kHtmlEmbedMaxEdge,
                  interpolation: img.Interpolation.average,
                ));
    // De metadata er expliciet afhalen. Opnieuw coderen doet dat NIET vanzelf:
    // de decoder leest de EXIF in en de encoder schrijft hem gewoon terug, dus
    // zonder deze twee regels reisde het cameramodel — en met een echte foto de
    // GPS-locatie en het opnametijdstip — mee naar iedereen die het rapport
    // krijgt. In een document dat over andermans beveiliging gaat.
    scaled.exif = img.ExifData();
    scaled.textData?.clear();
    return _hasTransparentPixel(scaled)
        ? (mime: 'image/png', bytes: img.encodePng(scaled))
        : (
            mime: 'image/jpeg',
            bytes: img.encodeJpg(scaled, quality: kHtmlEmbedJpegQuality),
          );
  } catch (e) {
    logWarning('encodeForHtmlEmbed: could not re-encode image', e);
    return null;
  }
}

/// Of [bytes] met een GIF-magisch getal begint (`GIF87a`/`GIF89a`). Op de
/// inhoud, niet op de bestandsnaam: de bron heeft niet altijd een `.gif`-naam,
/// en een verkeerd benoemd bestand mag de dimensiecontrole niet ontlopen.
bool _looksLikeGif(Uint8List bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0x47 && // G
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x38 && // 8
    (bytes[4] == 0x37 || bytes[4] == 0x39) && // 7 of 9
    bytes[5] == 0x61; // a

/// Sluit een GIF ongewijzigd in — met behoud van de beweging — mits zijn
/// logische scherm binnen [kMaxImageDecodeDimension] valt. Een groter canvas
/// wordt geweigerd: opnieuw coderen zou de animatie wissen, en insluiten zou de
/// ontvanger bij het openen gigabytes decodegeheugen per frame kosten (#1044).
HtmlEmbeddedImage? _embedGifIfBounded(Uint8List bytes, String source) {
  try {
    final probe = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (probe == null) return null;
    if (probe.width > kMaxImageDecodeDimension ||
        probe.height > kMaxImageDecodeDimension) {
      logWarning(
        'encodeForHtmlEmbed: GIF exceeds the decode cap, not embedded',
        source,
      );
      return null;
    }
    return (mime: 'image/gif', bytes: bytes);
  } catch (e) {
    logWarning('encodeForHtmlEmbed: could not probe GIF', e);
    return null;
  }
}

String? _passThroughFor(String source) {
  final lower = source.toLowerCase();
  for (final entry in _passThrough.entries) {
    if (lower.endsWith(entry.key)) return entry.value;
  }
  return null;
}

/// Of er werkelijk een doorzichtige pixel in [image] zit.
///
/// Niet `hasAlpha`: dat zegt alleen dát er een alfakanaal is, en een gewone
/// schermafdruk in PNG heeft dat kanaal vrijwel altijd zonder het te gebruiken.
/// Daarop afgaan zou elke schermafdruk als PNG insluiten — een factor tien
/// groter dan nodig, in het formaat waar een rapport er het meest van heeft.
bool _hasTransparentPixel(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

/// De `data:`-URI voor een ingesloten afbeelding.
String htmlImageDataUri(HtmlEmbeddedImage image) =>
    'data:${image.mime};base64,${base64Encode(image.bytes)}';
