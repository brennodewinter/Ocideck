/// Jaro- en Jaro-Winkler-gelijkenis tussen twee teksten.
///
/// Gebruikt om een getypt antwoord op een vraagslide te vergelijken met het
/// juiste antwoord: een typefout of een verbogen woord hoort niet meteen fout
/// te zijn, maar een ander antwoord wel. De auteur stelt zelf de drempel in.
///
/// Bewust een eigen implementatie in plaats van een pakket: het is twintig
/// regels rekenwerk, en elke afhankelijkheid erbij is er een die meegewogen,
/// gescand en verantwoord moet worden.
library;

/// Het gewicht van het gemeenschappelijke voorvoegsel in [jaroWinkler].
/// 0,1 is de waarde uit Winklers oorspronkelijke werk.
const double _prefixScale = 0.1;

/// Hoeveel beginletters hoogstens meetellen als voorvoegsel.
const int _maxPrefixLength = 4;

/// Alleen strings die al ten minste zo veel op elkaar lijken, krijgen de
/// voorvoegselbonus — anders tilt een toevallig gelijk begin twee heel
/// verschillende antwoorden over de drempel.
const double _boostThreshold = 0.7;

/// Jaro-gelijkenis: 0 (niets gemeen) tot 1 (identiek).
double jaro(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;

  final s1 = a.runes.toList();
  final s2 = b.runes.toList();

  // Twee tekens tellen als overeenkomst zolang ze niet verder dan dit uit
  // elkaar staan; dat maakt Jaro ongevoelig voor kleine verschuivingen.
  final window = (s1.length > s2.length ? s1.length : s2.length) ~/ 2 - 1;
  final reach = window < 0 ? 0 : window;

  final matched1 = List<bool>.filled(s1.length, false);
  final matched2 = List<bool>.filled(s2.length, false);

  var matches = 0;
  for (var i = 0; i < s1.length; i++) {
    final start = i - reach < 0 ? 0 : i - reach;
    final end = i + reach + 1 > s2.length ? s2.length : i + reach + 1;
    for (var j = start; j < end; j++) {
      if (matched2[j] || s1[i] != s2[j]) continue;
      matched1[i] = true;
      matched2[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;

  // Verwisselingen: overeenkomende tekens die in de andere volgorde staan.
  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < s1.length; i++) {
    if (!matched1[i]) continue;
    while (!matched2[k]) {
      k++;
    }
    if (s1[i] != s2[k]) transpositions++;
    k++;
  }

  final m = matches.toDouble();
  return (m / s1.length + m / s2.length + (m - transpositions / 2) / m) / 3;
}

/// Jaro-Winkler-gelijkenis: [jaro] met een bonus voor een gelijk begin.
/// Antwoorden beginnen doorgaans goed en lopen verderop uiteen, dus dat
/// beginstuk zegt meer dan het staartje.
double jaroWinkler(String a, String b) {
  final base = jaro(a, b);
  if (base < _boostThreshold) return base;
  final s1 = a.runes.toList();
  final s2 = b.runes.toList();
  final limit = [
    s1.length,
    s2.length,
    _maxPrefixLength,
  ].reduce((x, y) => x < y ? x : y);
  var prefix = 0;
  while (prefix < limit && s1[prefix] == s2[prefix]) {
    prefix++;
  }
  return base + prefix * _prefixScale * (1 - base);
}

/// Maak een antwoord vergelijkbaar: hoofdletters, randspaties en dubbele
/// spaties mogen het oordeel niet bepalen. Leestekens blijven staan — die
/// horen soms wél bij het antwoord, en de drempel vangt een losse punt op.
String normalizeAnswerText(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Het best passende van de [accepted] antwoorden bij [given], met de
/// bijbehorende gelijkenis.
///
/// Ook het antwoord zelf komt terug en niet alleen het cijfer: bij meerdere
/// goed gerekende antwoorden hoort de kijker achteraf te zien tegen wélk
/// antwoord het zijne is afgezet. Dat is doorgaans niet het eerste in de lijst.
/// [answer] is leeg wanneer er niets te vergelijken viel.
({String answer, double score}) bestAnswerMatch(
  String given,
  Iterable<String> accepted,
) {
  final needle = normalizeAnswerText(given);
  var best = 0.0;
  String? bestAnswer;
  for (final candidate in accepted) {
    if (normalizeAnswerText(candidate).isEmpty) continue;
    // Het eerste bruikbare antwoord is het vertrekpunt, zodat een leeg of
    // volstrekt afwijkend antwoord toch ergens tegen afgezet wordt.
    bestAnswer ??= candidate;
    if (needle.isEmpty) continue;
    final score = jaroWinkler(needle, normalizeAnswerText(candidate));
    if (score > best) {
      best = score;
      bestAnswer = candidate;
    }
  }
  return (answer: bestAnswer ?? '', score: best);
}

/// De beste gelijkenis van [given] met een van de [accepted] antwoorden, na
/// normalisatie. 0 wanneer er niets te vergelijken valt.
double bestAnswerSimilarity(String given, Iterable<String> accepted) =>
    bestAnswerMatch(given, accepted).score;
