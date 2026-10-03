import 'dart:convert';
import 'dart:typed_data';

/// De UTF-8-byte-order-mark: `EF BB BF`.
const List<int> utf8Bom = [0xEF, 0xBB, 0xBF];

/// Of [bytes] met een UTF-8-BOM begint.
bool startsWithUtf8Bom(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == utf8Bom[0] &&
    bytes[1] == utf8Bom[1] &&
    bytes[2] == utf8Bom[2];

/// Of `utf8.decode` zelf één leidende BOM weglaat. Dart doet dat op de VM
/// (gemeten op 2026-09-30), maar de regel staat nergens als belofte en een
/// andere backend (web, wasm) mag er anders over denken. Eén keer gepeild in
/// plaats van aangenomen, zodat [decodeUtf8KeepingBomFlag] op elk platform
/// precies één BOM van de tekst afhaalt.
final bool _decoderDropsBom = utf8.decode(utf8Bom).isEmpty;

/// Decodeert [bytes] als UTF-8 en onthoudt of er een BOM voorop stond.
///
/// De tekst is altijd **zonder** die ene BOM: zo zien de front-matter-detectie,
/// de koppenlijst en de editor geen onzichtbaar teken voor de eerste regel. De
/// BOM reist als vlag mee en gaat bij het schrijven terug via [encodeUtf8WithBom].
///
/// Alleen de eerste `EF BB BF` is de markering; een tweede is gewoon tekst
/// (U+FEFF) en blijft staan, zodat decoderen en weer coderen de bytes exact
/// teruggeeft. Daarom decodeert dit de hélé invoer en knipt niet zelf drie bytes
/// eraf: de decoder zou dan de tweede BOM alsnog als "de eerste" opeten.
///
/// Gooit een [FormatException] bij ongeldige UTF-8, net als `utf8.decode`.
({String text, bool hasBom}) decodeUtf8KeepingBomFlag(List<int> bytes) {
  final hasBom = startsWithUtf8Bom(bytes);
  final text = utf8.decode(bytes);
  return (
    text: hasBom && !_decoderDropsBom ? text.substring(1) : text,
    hasBom: hasBom,
  );
}

/// Het omgekeerde van [decodeUtf8KeepingBomFlag]: [text] als UTF-8, met de BOM
/// ervoor wanneer [hasBom].
Uint8List encodeUtf8WithBom(String text, {required bool hasBom}) {
  final body = utf8.encode(text);
  if (!hasBom) return body;
  return Uint8List(utf8Bom.length + body.length)
    ..setAll(0, utf8Bom)
    ..setAll(utf8Bom.length, body);
}
