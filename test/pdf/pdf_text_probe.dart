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

/// De zichtbare tekst per inhoudsstroom — voor een tekst-PDF is dat één
/// stroom per bladzijde, in documentvolgorde.
///
/// Waarom naast [pdfVisibleText]: sommige vragen gaan over wát er op één blad
/// staat en niet of het ergens in het bestand voorkomt. "Staat de kopregel van
/// een tabel alleen op een blad, zonder een enkele inhoudsrij?" is er zo een
/// (#1790).
List<String> pdfVisibleTextPerPage(Uint8List bytes) => [
  for (final stream in _inflatedStreams(bytes))
    [
      for (final match in _literalString.allMatches(stream))
        _unescape(match.group(1)!),
    ].join(' '),
];

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

/// De sneden die het bestand werkelijk aanroept, op naam.
///
/// Waarom dit bestaat: "staat de kop vet" is met de tekst alleen niet te
/// beantwoorden — die is in beide gevallen dezelfde letters. De vraag is wélke
/// snede het bestand ervoor aanroept, en dat staat als `/BaseFont` gewoon in het
/// fontobject. De veertien standaardsneden worden niet ingebed, dus dit is
/// tevens de enige plek waar het antwoord te vinden is.
Set<String> pdfBaseFonts(Uint8List bytes) => {
  for (final match in _baseFont.allMatches(latin1.decode(bytes)))
    match.group(1)!,
};

/// Het aantal afbeeldingen in het bestand.
///
/// Eén logo op vijfentwintig bladzijden hoort één afbeelding te zijn (plus
/// hoogstens zijn doorzichtigheidsmasker), niet vijfentwintig.
int pdfImageCount(Uint8List bytes) =>
    RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(bytes)).length;

/// De vulkleuren die het bestand zet, als (rood, groen, blauw) van 0 tot 1.
///
/// De `rg`-opdracht in de inhoudsstroom is het enige spoor van een vlak achter
/// tekst: een achtergrond staat nergens als eigenschap in het bestand, alleen
/// als een rechthoek die met die kleur gevuld wordt.
List<List<double>> pdfFillColors(Uint8List bytes) => [
  for (final stream in _inflatedStreams(bytes))
    for (final match in _fillColor.allMatches(stream))
      [
        double.parse(match.group(1)!),
        double.parse(match.group(2)!),
        double.parse(match.group(3)!),
      ],
];

/// De getekende lijnstukken uit alle inhoudsstromen, als `[x1, y1, x2, y2]`.
///
/// `package:pdf` tekent een onderstreping als één `drawLine` + `strokePath`,
/// wat in de stroom neerkomt op `x y m  x y l  S`. Eén link hoort dus één
/// lijnstuk op te leveren; telt hij er meer op dezelfde hoogte, dan is de
/// onderstreping per woord getekend in plaats van als één geheel (#1792).
List<List<double>> pdfStrokedLines(Uint8List bytes) => [
  for (final stream in _inflatedStreams(bytes))
    for (final match in _strokedLine.allMatches(stream))
      [for (var group = 1; group <= 4; group++) double.parse(match.group(group)!)],
];

final _strokedLine = RegExp(
  r'(-?[\d.]+)\s+(-?[\d.]+)\s+m\s+(-?[\d.]+)\s+(-?[\d.]+)\s+l',
);

final _literalString = RegExp(r'\(((?:[^()\\]|\\.)*)\)');
final _baseFont = RegExp(r'/BaseFont\s*/([A-Za-z0-9-]+)');
final _fillColor = RegExp(
  r'([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+rg(?![A-Za-z])',
);
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
