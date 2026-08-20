// Leest de zichtbare tekst terug uít een PDF-bestand.
//
// Waarom dit hulpje bestaat: een test die alleen de blokken vóór het tekenen
// controleert, bewijst dat de *bedoeling* klopt — niet dat het bestand die
// bedoeling ook draagt. Juist bij een fail-closed privacytest is dat het hele
// punt: de vraag is of het geredigeerde gegeven écht niet in het geleverde
// bestand staat, niet of de laag ervoor hem netjes had weggehaald.
//
// Hoe het werkt: de tekst van de veertien standaardsneden wordt in een PDF als
// gewone (WinAnsi-)tekens in de inhoudsstroom geschreven, tussen haakjes en
// gevolgd door `Tj` of `TJ`. Die stromen zijn samengeperst met zlib; dit hulpje
// pakt ze uit en haalt de letterlijke stukken eruit.
//
// Wat het NIET ziet: tekst die op het terugvalfont is gezet (alles buiten
// Latin-1). Die staat als glyph-nummers in het bestand en is zonder de
// font-tabellen niet terug te lezen. Tests die op de tekst zelf willen
// controleren, gebruiken dus Latijnse tekst.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// De letterlijke stukken tekst uit alle inhoudsstromen van [bytes],
/// aaneengeregen met een spatie ertussen.
String pdfVisibleText(Uint8List bytes) {
  final text = StringBuffer();
  for (final stream in _inflatedStreams(bytes)) {
    for (final match in _literalString.allMatches(stream)) {
      text
        ..write(_unescape(match.group(1)!))
        ..write(' ');
    }
  }
  return text.toString();
}

/// Het aantal bladzijden, geteld aan de `/Type /Page`-objecten.
int pdfPageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;

/// De titels in de bladwijzerboom, in de volgorde waarin ze in het bestand
/// staan. Bladwijzertitels staan niet in een samengeperste stroom maar gewoon in
/// het object zelf.
List<String> pdfOutlineTitles(Uint8List bytes) => [
  for (final match in _outlineTitle.allMatches(latin1.decode(bytes)))
    _unescape(match.group(1)!),
];

final _literalString = RegExp(r'\(((?:[^()\\]|\\.)*)\)');
final _outlineTitle = RegExp(r'/Title\s*\(((?:[^()\\]|\\.)*)\)');

/// Alle uitgepakte inhoudsstromen. Een stroom die niet met zlib is samengeperst
/// (of die niet uitpakt) wordt overgeslagen: die draagt dan geen tekst die dit
/// hulpje kan lezen.
Iterable<String> _inflatedStreams(Uint8List bytes) sync* {
  final raw = latin1.decode(bytes);
  var index = 0;
  while (true) {
    final start = raw.indexOf('stream', index);
    if (start < 0) return;
    final end = raw.indexOf('endstream', start);
    if (end < 0) return;
    index = end + 'endstream'.length;
    // Achter `stream` staat een regelovergang die niet bij de gegevens hoort.
    var from = start + 'stream'.length;
    if (from < raw.length && raw.codeUnitAt(from) == 0x0D) from++;
    if (from < raw.length && raw.codeUnitAt(from) == 0x0A) from++;
    final data = bytes.sublist(from, end);
    try {
      yield latin1.decode(zlib.decode(data), allowInvalid: true);
    } on FormatException {
      yield latin1.decode(data, allowInvalid: true);
    }
  }
}

/// De ontsnappingen die een PDF-tekenreeks kent, terug naar gewone tekens.
String _unescape(String value) =>
    value.replaceAll(r'\(', '(').replaceAll(r'\)', ')').replaceAll(r'\\', r'\');
