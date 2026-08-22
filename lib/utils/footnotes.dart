/// Voetnoten in een plat-Markdown-document: `[^1]` in de tekst, `[^1]: de
/// noot` als definitie.
///
/// Geen eigen vinding: dit is de voetnootsyntaxis van Pandoc, die GitHub,
/// Obsidian en de meeste andere lezers ook kennen. Daarmee blijft een document
/// mét voetnoten precies wat FILE_FORMAT.md §14.1 belooft — een `.md` die
/// overal opengaat en overal hetzelfde betekent, zonder dat de lezer iets van
/// OciDeck hoeft te weten.
///
/// Alles hier is een zuivere tekstbewerking, zodat de regels los van de
/// weergave uitputtend te toetsen zijn. De weergave, de vellen en de exports
/// delen deze ene ontleding; liepen ze uiteen, dan zou een noot op het scherm
/// een ander nummer krijgen dan in de druk.
library;

/// Eén voetnoot van een document.
class Footnote {
  const Footnote({
    required this.label,
    required this.text,
    required this.number,
  });

  /// Het label zoals de auteur het schreef: `1`, maar net zo goed `bron`. Het
  /// blijft in het bestand staan en wordt nooit herschreven.
  final String label;

  /// De tekst van de noot, met inline-opmaak er nog in.
  final String text;

  /// Het volgnummer in leesvolgorde — wat de lezer ziet. Verwijst de tekst
  /// twee keer naar hetzelfde label, dan is dat twee keer hetzelfde nummer.
  ///
  /// Doornummeren en niet het label tonen, omdat een label geen volgorde
  /// belooft: wie er eentje tussenvoegt zou anders alles met de hand moeten
  /// hernummeren. Pandoc doet het net zo.
  final int number;

  @override
  bool operator ==(Object other) =>
      other is Footnote &&
      other.label == label &&
      other.text == text &&
      other.number == number;

  @override
  int get hashCode => Object.hash(label, text, number);

  @override
  String toString() => 'Footnote($number, $label, $text)';
}

/// Een definitieregel: `[^label]: tekst`, hooguit drie spaties ingesprongen.
/// `multiLine` zodat `^` op élke regel matcht, niet alleen de eerste —
/// anders mist `nextFootnoteLabel` een definitie die niet op regel 0 staat.
final _definitionStart = RegExp(
  r'^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$',
  multiLine: true,
);

/// Een verwijzing in de lopende tekst: `[^label]`, niet gevolgd door een
/// dubbele punt (dat is een definitie).
final _reference = RegExp(r'\[\^([^\]\s]+)\](?!:)');

final _fence = RegExp(r'^\s*(```|~~~)');

/// De labels waarnaar [text] verwijst, in volgorde van voorkomen. Herhalingen
/// blijven staan: de aanroeper die uniek wil, ontdubbelt zelf.
List<String> footnoteReferencesIn(String text) => [
  for (final match in _reference.allMatches(text)) match.group(1)!,
];

/// [markdown] zonder de definitieregels — de tekst zoals hij gelezen hoort te
/// worden.
///
/// Een definitie is geen alinea: hem gewoon laten staan zou de noot midden in
/// de lopende tekst tonen, op de plek waar de auteur hem toevallig had
/// geparkeerd. De aanroeper haalt de noten met [documentFootnotes] op en zet ze
/// waar ze horen: onderaan het vel of achterin.
String stripFootnoteDefinitions(String markdown) {
  if (!markdown.contains('[^')) return markdown;
  final lines = markdown.split('\n');
  final kept = <String>[];
  var index = 0;
  var fenced = false;
  while (index < lines.length) {
    final line = lines[index];
    if (_fence.hasMatch(line)) fenced = !fenced;
    if (!fenced && _definitionStart.hasMatch(line)) {
      index = _endOfDefinition(lines, index);
      // De lege regel die op de definitie volgde hoort bij de definitie: laten
      // staan zou er een gat achterlaten waar de noot stond.
      if (index < lines.length && lines[index].trim().isEmpty) index++;
      // …en een gat aan het begin of een dubbele witregel middenin evenmin.
      while (kept.isNotEmpty &&
          kept.last.trim().isEmpty &&
          (index >= lines.length || lines[index].trim().isEmpty)) {
        kept.removeLast();
      }
      continue;
    }
    kept.add(line);
    index++;
  }
  final stripped = kept.join('\n');
  // Een document dat op een regeleinde eindigde, eindigt daar nog steeds op.
  // Zonder deze correctie at het opruimen van de witregel ónder een afsluitende
  // definitie ook de laatste regelovergang op.
  if (markdown.endsWith('\n') && !stripped.endsWith('\n')) {
    return '$stripped\n';
  }
  return stripped;
}

/// De voetnoten van [markdown], genummerd in de volgorde waarin de tekst er
/// naar verwijst.
///
/// Een definitie waar niets naar verwijst komt er niet in: er is geen plek in
/// de tekst waar de lezer hem zou tegenkomen, en een noot met een nummer maar
/// zonder merkteken is een raadsel. Hij blijft wel gewoon in het bestand staan.
/// Een verwijzing zonder definitie is andersom geen voetnoot maar tekst — zo
/// leest Pandoc het ook, en zo blijft `[^1]` in een technische tekst gewoon
/// `[^1]`.
List<Footnote> documentFootnotes(String markdown) {
  if (!markdown.contains('[^')) return const [];
  final defined = _definitions(markdown);
  if (defined.isEmpty) return const [];
  final body = stripFootnoteDefinitions(markdown);
  final notes = <Footnote>[];
  final seen = <String>{};
  for (final label in footnoteReferencesIn(body)) {
    if (!defined.containsKey(label) || !seen.add(label)) continue;
    notes.add(
      Footnote(label: label, text: defined[label]!, number: notes.length + 1),
    );
  }
  return notes;
}

/// Label → volgnummer, voor wie bij een verwijzing het nummer moet weten.
Map<String, int> footnoteNumbers(String markdown) => {
  for (final note in documentFootnotes(markdown)) note.label: note.number,
};

/// Of [markdown] een voetnoot bevat die ook echt als noot leest — een
/// verwijzing mét definitie.
bool hasFootnotes(String markdown) => documentFootnotes(markdown).isNotEmpty;

/// De definities in [markdown]: label → tekst, in bronvolgorde. Een label dat
/// twee keer wordt gedefinieerd houdt de eerste tekst; dat is wat Pandoc doet,
/// en stilzwijgend de laatste nemen zou de eerste noot laten verdwijnen.
Map<String, String> _definitions(String markdown) {
  final lines = markdown.split('\n');
  final out = <String, String>{};
  var index = 0;
  var fenced = false;
  while (index < lines.length) {
    final line = lines[index];
    if (_fence.hasMatch(line)) fenced = !fenced;
    final match = fenced ? null : _definitionStart.firstMatch(line);
    if (match == null) {
      index++;
      continue;
    }
    final end = _endOfDefinition(lines, index);
    final rest = [
      match.group(2)!.trim(),
      for (var i = index + 1; i < end; i++) lines[i].trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    out.putIfAbsent(match.group(1)!, () => rest);
    index = end;
  }
  return out;
}

/// De index van de eerste regel ná de definitie die op [start] begint.
///
/// Een noot mag doorlopen op de volgende regel, mits die is ingesprongen —
/// dezelfde regel als Pandoc, en de enige die een gewone alinea eronder niet
/// per ongeluk opslokt.
int _endOfDefinition(List<String> lines, int start) {
  var end = start + 1;
  while (end < lines.length &&
      lines[end].trim().isNotEmpty &&
      (lines[end].startsWith('    ') || lines[end].startsWith('\t'))) {
    end++;
  }
  return end;
}

/// Het eerstvolgende vrije getal als label voor een nieuwe voetnoot in
/// [markdown].
///
/// Een getal en geen woord: `[^1]` is wat iedereen schrijft, en het label is
/// toch niet wat de lezer ziet — de weergave nummert door op leesvolgorde. Wie
/// een sprekend label wil (`[^bron]`) typt dat met de hand; dat blijft staan.
String nextFootnoteLabel(String markdown) {
  final used = <String>{
    ...footnoteReferencesIn(markdown),
    for (final match in _definitionStart.allMatches(markdown)) match.group(1)!,
  };
  var next = 1;
  while (used.contains('$next')) {
    next++;
  }
  return '$next';
}

/// [source] met een voetnoot met [label] erin: het merkteken op de cursor (of
/// in plaats van de selectie tussen [start] en [end]), de lege definitie
/// onderaan.
///
/// Levert de nieuwe tekst plus de plek waar de cursor hoort te komen: áchter de
/// dubbele punt van de definitie, want dat is waar je nu gaat typen. De
/// bronstand kent geen twee cursors, en de noot invullen is het echte werk —
/// het merkteken staat er al.
(String, int) insertFootnoteIntoSource(
  String source,
  int start,
  int end,
  String label,
) {
  final from = start.clamp(0, source.length);
  final to = end.clamp(from, source.length);
  final marker = '[^$label]';
  final withMarker = source.replaceRange(from, to, marker);
  final definition = '[^$label]: ';
  // Precies één witregel tussen de tekst en de definitie; een bestand dat al op
  // een regeleinde eindigde krijgt er niet nog eens twee bij.
  final separator = withMarker.trimRight().isEmpty
      ? ''
      : (withMarker.endsWith('\n\n')
            ? ''
            : (withMarker.endsWith('\n') ? '\n' : '\n\n'));
  final next = '$withMarker$separator$definition';
  return (next, next.length);
}
