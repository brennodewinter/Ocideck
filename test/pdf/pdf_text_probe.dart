// Leest de zichtbare tekst terug uít een PDF-bestand.
//
// Waarom dit hulpje bestaat: een test die alleen de blokken vóór het tekenen
// controleert, bewijst dat de *bedoeling* klopt — niet dat het bestand die
// bedoeling ook draagt. Juist bij een fail-closed privacytest is dat het hele
// punt: de vraag is of het geredigeerde gegeven écht niet in het geleverde
// bestand staat, niet of de laag ervoor hem netjes had weggehaald.
//
// De standaardsneden schrijven letterlijke WinAnsi-tekst. Ingesloten fonts
// schrijven hexadecimale glyph-codes die hun ToUnicode-tabel decodeert.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// De letterlijke stukken tekst uit alle inhoudsstromen van [bytes],
/// aaneengeregen met een spatie ertussen.
String pdfVisibleText(Uint8List bytes) =>
    pdfVisibleTextPerPage(bytes).join(' ');

/// De zichtbare tekst per pagina-inhoudsstroom, in documentvolgorde.
List<String> pdfVisibleTextPerPage(Uint8List bytes) {
  final source = latin1.decode(bytes);
  final streams = Map.fromEntries(_pdfStreams(bytes));
  final unicodeMaps = {
    for (final font in _fontUnicodeRef.allMatches(source))
      font.group(1)!: _unicodeMappings(streams[int.parse(font.group(2)!)]!),
  };
  return [
    for (final stream in streams.values)
      if (_textBlock.hasMatch(stream))
        [
          for (final block in _textBlock.allMatches(stream))
            ..._textRuns(block.group(2)!, unicodeMaps[block.group(1)]),
        ].join(' '),
  ];
}

final _fontUnicodeRef = RegExp(
  r'/Name/(F\d+)(?:(?!endobj)[\s\S])*?/ToUnicode\s+(\d+) 0 R',
);
final _textBlock = RegExp(r'\bBT\s+/(F\d+)\s+([\s\S]*?)\bET\b');
final _unicodePair = RegExp(
  r'^<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]+)>$',
  multiLine: true,
);
final _hexString = RegExp(r'<([0-9A-Fa-f]+)>');
final _utf16Hex = RegExp(r'[0-9A-Fa-f]{4}');

Map<String, String> _unicodeMappings(String stream) => {
  for (final section in RegExp(
    r'beginbfchar\n([\s\S]*?)endbfchar',
  ).allMatches(stream))
    for (final pair in _unicodePair.allMatches(section.group(1)!))
      pair.group(1)!.toUpperCase(): String.fromCharCodes(
        _utf16Hex
            .allMatches(pair.group(2)!)
            .map((match) => int.parse(match.group(0)!, radix: 16)),
      ),
};

Iterable<String> _textRuns(String text, Map<String, String>? unicode) {
  if (unicode == null) {
    return _literalString.allMatches(text).map((m) => _unescape(m.group(1)!));
  }
  return _hexString
      .allMatches(text)
      .map(
        (run) => _utf16Hex
            .allMatches(run.group(1)!)
            .map((glyph) => unicode[glyph.group(0)!.toUpperCase()] ?? '\uFFFD')
            .join(),
      );
}

/// Baselines of matching literal text runs in the rendered PDF content.
List<double> pdfTextBaselines(Uint8List bytes, String text) => [
  for (final stream in _inflatedStreams(bytes))
    for (final block in RegExp(r'\bBT\b[\s\S]*?\bET\b').allMatches(stream))
      if (_literalString
          .allMatches(block.group(0)!)
          .any((m) => _unescape(m.group(1)!).trim() == text))
        for (final point in RegExp(
          r'(-?[\d.]+)\s+(-?[\d.]+)\s+Td',
        ).allMatches(block.group(0)!))
          double.parse(point.group(2)!),
];

/// Number of distinct painted text baselines in each text page stream.
List<int> pdfLineCountsPerPage(Uint8List bytes) => [
  for (final stream in _inflatedStreams(bytes))
    if (RegExp(r'\bBT\b').hasMatch(stream))
      RegExp(r'(-?[\d.]+)\s+(-?[\d.]+)\s+Td')
          .allMatches(stream)
          .map((m) => (double.parse(m.group(2)!) * 100).round())
          .toSet()
          .length,
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
      [
        for (var group = 1; group <= 4; group++)
          double.parse(match.group(group)!),
      ],
];

final _strokedLine = RegExp(
  r'(-?[\d.]+)\s+(-?[\d.]+)\s+m\s+(-?[\d.]+)\s+(-?[\d.]+)\s+l',
);

final _literalString = RegExp(r'\(((?:[^()\\]|\\.)*)\)');
final _baseFont = RegExp(r'/BaseFont\s*/([A-Za-z0-9-]+)');
final _fillColor = RegExp(
  r'([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+rg(?![A-Za-z])',
);

/// De getekende afbeeldingsvlakken uit alle inhoudsstromen, als
/// `(breedte, hoogte)` in punten.
///
/// `package:pdf` zet een afbeelding neer als `w 0 0 h x y cm /Naam Do`: de
/// eerste twee getallen van de plaatsingsmatrix zijn de schaal op beide assen,
/// dus de afmeting die het beeld op papier krijgt. Daarmee meet een test wat
/// de lezer straks ziet, niet wat de code van plan was (#2462).
List<(double, double)> pdfDrawnImageBoxes(Uint8List bytes) => [
  for (final stream in _inflatedStreams(bytes))
    for (final match in _drawnImage.allMatches(stream))
      (double.parse(match.group(1)!), double.parse(match.group(2)!)),
];

final _drawnImage = RegExp(
  r'(-?[\d.]+)\s+0\s+0\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+cm\s*/\S+\s+Do',
);
final _outlineTitle = RegExp(r'/Title\s*\(((?:[^()\\]|\\.)*)\)');

/// Alle uitgepakte inhoudsstromen. Een stroom die niet met zlib is samengeperst
/// (of die niet uitpakt) wordt overgeslagen: die draagt dan geen tekst die dit
/// hulpje kan lezen.
Iterable<String> _inflatedStreams(Uint8List bytes) =>
    _pdfStreams(bytes).map((entry) => entry.value);

final _streamStart = RegExp(
  r'^(\d+) 0 obj\r?\n<<[^\n]*>>[ \r\n]*stream\r?\n',
  multiLine: true,
);

Iterable<MapEntry<int, String>> _pdfStreams(Uint8List bytes) sync* {
  final raw = latin1.decode(bytes);
  for (final stream in _streamStart.allMatches(raw)) {
    final end = raw.indexOf('endstream', stream.end);
    if (end < 0) return;
    final data = bytes.sublist(stream.end, end);
    final id = int.parse(stream.group(1)!);
    try {
      yield MapEntry(id, latin1.decode(zlib.decode(data)));
    } on FormatException {
      yield MapEntry(id, latin1.decode(data));
    }
  }
}

/// De ontsnappingen die een PDF-tekenreeks kent, terug naar gewone tekens.
String _unescape(String value) =>
    value.replaceAll(r'\(', '(').replaceAll(r'\)', ')').replaceAll(r'\\', r'\');
