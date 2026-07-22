/// Verschilbepaling tussen twee korte teksten, teken voor teken.
///
/// Gebruikt om na een fout getypt antwoord te laten zien wáár het misging: niet
/// alleen "fout", maar welke letters er te veel stonden en welke er misten. Dat
/// is het verschil tussen een cijfer en een les.
///
/// Bewust een eigen implementatie: het is de klassieke langste-gemeenschappelijke-
/// deelrij, en een pakket erbij voor dertig regels is er een die meegewogen,
/// gescand en verantwoord moet worden.
library;

/// Waar een stukje tekst vandaan komt.
///
/// - [same]: staat in beide teksten.
/// - [onlyLeft]: staat alleen links (in het getypte antwoord: te veel).
/// - [onlyRight]: staat alleen rechts (in het juiste antwoord: gemist).
enum TextDiffKind { same, onlyLeft, onlyRight }

/// Een aaneengesloten stuk tekst met één herkomst.
class TextDiffSegment {
  final String text;
  final TextDiffKind kind;

  const TextDiffSegment(this.text, this.kind);

  @override
  String toString() => '${kind.name}:$text';

  @override
  bool operator ==(Object other) =>
      other is TextDiffSegment && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);
}

/// Boven deze lengte wordt er niet meer teken voor teken vergeleken. De
/// vergelijking kost lengte × lengte aan werk, en een antwoord van duizend
/// tekens is geen antwoord meer — dan is "dit stond er, dit hoorde er te staan"
/// even behulpzaam en oneindig veel goedkoper.
const int textDiffMaxLength = 400;

/// Vergelijk [left] en [right] teken voor teken en geef de stukken terug in
/// leesvolgorde.
///
/// Hoofdletters tellen niet mee in de vergelijking — ze worden ook niet
/// meegewogen bij het goedrekenen van een antwoord, dus ze als fout aanwijzen
/// zou de kijker op het verkeerde been zetten. De teruggegeven tekst is wél de
/// oorspronkelijke, mét hoofdletters.
List<TextDiffSegment> diffText(String left, String right) {
  if (left == right) {
    return left.isEmpty ? const [] : [TextDiffSegment(left, TextDiffKind.same)];
  }
  if (left.isEmpty) return [TextDiffSegment(right, TextDiffKind.onlyRight)];
  if (right.isEmpty) return [TextDiffSegment(left, TextDiffKind.onlyLeft)];

  final a = left.runes.toList();
  final b = right.runes.toList();
  if (a.length > textDiffMaxLength || b.length > textDiffMaxLength) {
    return [
      TextDiffSegment(left, TextDiffKind.onlyLeft),
      TextDiffSegment(right, TextDiffKind.onlyRight),
    ];
  }

  final foldedA = _folded(a);
  final foldedB = _folded(b);

  // Langste gemeenschappelijke deelrij: lengths[i][j] is de lengte daarvan voor
  // de staarten a[i..] en b[j..].
  final lengths = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
    growable: false,
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = foldedA[i] == foldedB[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }

  final segments = <TextDiffSegment>[];
  final buffer = StringBuffer();
  TextDiffKind? open;

  void flush() {
    if (open != null && buffer.isNotEmpty) {
      segments.add(TextDiffSegment(buffer.toString(), open!));
    }
    buffer.clear();
  }

  void emit(int rune, TextDiffKind kind) {
    if (kind != open) {
      flush();
      open = kind;
    }
    buffer.writeCharCode(rune);
  }

  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (foldedA[i] == foldedB[j]) {
      emit(a[i], TextDiffKind.same);
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      emit(a[i], TextDiffKind.onlyLeft);
      i++;
    } else {
      emit(b[j], TextDiffKind.onlyRight);
      j++;
    }
  }
  while (i < a.length) {
    emit(a[i], TextDiffKind.onlyLeft);
    i++;
  }
  while (j < b.length) {
    emit(b[j], TextDiffKind.onlyRight);
    j++;
  }
  flush();
  return segments;
}

/// De stukken die in [left] thuishoren: wat klopte en wat er te veel stond.
List<TextDiffSegment> leftSide(List<TextDiffSegment> diff) => [
  for (final s in diff)
    if (s.kind != TextDiffKind.onlyRight) s,
];

/// De stukken die in [right] thuishoren: wat klopte en wat er gemist is.
List<TextDiffSegment> rightSide(List<TextDiffSegment> diff) => [
  for (final s in diff)
    if (s.kind != TextDiffKind.onlyLeft) s,
];

List<int> _folded(List<int> runes) => [
  for (final r in runes) String.fromCharCode(r).toLowerCase().runes.first,
];
