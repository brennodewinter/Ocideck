/// De maat van een afbeelding in de haakjes van `![…](bron)` — Marp's eigen
/// vocabulaire (`w:`/`h:`), in documenten hetzelfde gehonoreerd.
///
/// `![w:50% Kat](kat.png)` toont de kat op de helft van de kolombreedte,
/// `![h:120 Handtekening](handtekening.png)` begrenst de hoogte op 120 px.
/// De tokens staan vóór de alt-tekst; wat geen maattoken is, blijft alt.
///
/// Waarom deze syntaxis en geen eigen truc: Marp kent `w:`/`h:` al — een
/// document dat OciDeck verlaat blijft in elke Marp-bewerker netjes op maat,
/// en elke andere Markdown-lezer toont de afbeelding gewoon (de token leest
/// mee als alt-tekst). Dezelfde reden als de rest van het formaat: de
/// uitlegbaarste variant die het doel bereikt.
library;

/// De gevraagde maat van een afbeelding: [width] in px, [widthFraction] als
/// deel van de beschikbare breedte (`w:50%`), en/of [height] in px. Een leeg
/// record (`null` overal) betekent: op natuurlijke maat tonen.
typedef ImageSize = ({double? width, double? widthFraction, double? height});

/// `w:200`, `w:200px`, `w:50%`, `h:120` — met de lange `width:`/`height:` die
/// Marp óók kent meegepakt, zodat een bewerkte bron terugleest wat hij schreef.
final _sizeToken = RegExp(
  r'^(?:w|h|width|height):(\d+(?:\.\d+)?)(%|px)?$',
  caseSensitive: false,
);

final _whitespace = RegExp(r'\s+');

/// Een `![…](…)`-regel, opgeknipt in de haakjes en de bestemming (die met
/// haakjes, titel en al letterlijk blijft).
final _imageMarkdown = RegExp(r'^!\[([^\]]*)\](\(.*\))\s*$');

/// Splitst de tekst tussen `![` en `]` in de gevraagde [ImageSize] en de
/// alt-tekst die overblijft. `w:50% Kat` → alt `Kat`, fraction 0.5.
({String alt, ImageSize size}) splitImageSizeTokens(String bracket) {
  double? width, height, fraction;
  final altWords = <String>[];
  for (final word in bracket.trim().split(_whitespace)) {
    if (word.isEmpty) continue;
    final match = _sizeToken.firstMatch(word);
    if (match == null) {
      altWords.add(word);
      continue;
    }
    final value = double.parse(match.group(1)!);
    if (word.toLowerCase().startsWith('h')) {
      height = value;
    } else if (match.group(2) == '%') {
      fraction = value / 100;
    } else {
      width = value;
    }
  }
  return (
    alt: altWords.join(' '),
    size: (width: width, widthFraction: fraction, height: height),
  );
}

/// Schrijft [size] vooraan in de haakjes van bestaande `![…](…)`-markdown:
/// oude maattokens gaan weg, de alt-tekst en de bestemming (pad, titel)
/// blijven letterlijk staan. Tekst die geen afbeeldingsregel is, komt
/// ongemoeid terug — dat kan nooit kwaad.
String markdownImageWithSize(String markdown, ImageSize size) {
  final match = _imageMarkdown.firstMatch(markdown.trim());
  if (match == null) return markdown;
  final alt = splitImageSizeTokens(match.group(1)!).alt;
  final bracket = [...imageSizeTokens(size), if (alt.isNotEmpty) alt].join(' ');
  return '![$bracket]${match.group(2)}';
}

/// De maattokens in schrijfvorm: `w:50%`, `w:200px`, `h:120px` — in deze
/// volgorde, zodat elke weg naar dezelfde tekst leidt.
List<String> imageSizeTokens(ImageSize size) => [
  if (size.widthFraction != null) 'w:${_num(size.widthFraction! * 100)}%',
  if (size.width != null) 'w:${_num(size.width!)}px',
  if (size.height != null) 'h:${_num(size.height!)}px',
];

/// `200.0` → `200`, `62.5` → `62.5` — geen `.0`-staarten in de bron.
String _num(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
