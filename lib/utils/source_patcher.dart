import 'dart:math' as math;

/// Past bewerkingen uit de visuele editor toe op de originele bron, in plaats
/// van de hele round-trip-uitvoer te overschrijven.
///
/// De visuele editor (Quill) round-tript Markdown → Quill → Markdown, en die
/// weg is niet byte-getrouw: witregels rond koppen, tabelscheidingsregels en
/// lijstvolgorde schuiven. Wie één woord aan een kop toevoegt in Visueel en
/// opslaat, krijgt tientallen spookwijzigingen in de diff.
///
/// Deze functie vergelijkt drie versies van de bron:
///
/// - [original]: de bron zoals die op schijf stond bij het laden.
/// - [baseline]: `roundTrip(original)` — wat de codec produceert zónder
///   bewerkingen. De normalisatie zichtbaar gemaakt.
/// - [current]: wat de notifier nu vasthoudt — `roundTrip(original)` mét de
///   bewerkingen van de gebruiker.
///
/// De diff tussen [baseline] en [current] zijn precies de bewerkingen die de
/// gebruiker maakte. We mappen elke baseline-regel naar de overeenkomende
/// regel in [original] (via LCS, met inhoudsfallback voor regels die de
/// round-trip verplaatste), en passen de bewerkingen daar toe. Zo blijft
/// alles wat de gebruiker niet aanraakte byte-getrouw.
///
/// Werkt op regelniveau (met `\n` als scheider), want de normalisatie
/// verplaatst hele regels, niet tekens binnen een regel.
String patchVisualEdits({
  required String original,
  required String baseline,
  required String current,
}) {
  if (baseline == current) return original;

  final origLines = original.split('\n');
  final baseLines = baseline.split('\n');
  final currLines = current.split('\n');

  // Stap 1: mappen baseline-regel → original-regel via LCS.
  final align = _alignLines(origLines, baseLines);

  // Stap 2: diff baseline → current (gebruikersbewerkingen).
  final hunks = _lcsDiff(baseLines, currLines);

  // Stap 3: bouw het resultaat op basis van original, met bewerkingen
  // toegepast op de overeenkomende posities.
  return _applyEdits(origLines, baseLines, currLines, align, hunks);
}

/// Mapt elke regel in [b] naar de overeenkomende regel in [a] via LCS.
/// Retourneert een lijst waar index i de index in [a] geeft voor b[i],
/// of -1 als er geen overeenkomst is.
List<int> _alignLines(List<String> a, List<String> b) {
  final m = a.length, n = b.length;
  final dp = List<List<int>>.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  final align = List<int>.filled(n, -1);
  var i = 0, j = 0;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      align[j] = i;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return align;
}

/// Een reeks opeenvolgende regels die gelijk zijn of verschillen.
class _Hunk {
  final bool equal;
  final int baselineStart;
  final int baselineEnd; // exclusief
  final int currentStart;
  final int currentEnd; // exclusief

  const _Hunk({
    required this.equal,
    required this.baselineStart,
    required this.baselineEnd,
    required this.currentStart,
    required this.currentEnd,
  });
}

/// LCS-gebaseerde diff. Geeft hunks terug die baseline in current omzetten.
List<_Hunk> _lcsDiff(List<String> a, List<String> b) {
  final m = a.length, n = b.length;
  final dp = List<List<int>>.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  final hunks = <_Hunk>[];
  var i = 0, j = 0;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      final s = i;
      while (i < m && j < n && a[i] == b[j]) {
        i++;
        j++;
      }
      hunks.add(
        _Hunk(
          equal: true,
          baselineStart: s,
          baselineEnd: i,
          currentStart: s,
          currentEnd: i,
        ),
      );
    } else {
      final sI = i, sJ = j;
      while (i < m && j < n && a[i] != b[j]) {
        if (dp[i + 1][j] >= dp[i][j + 1]) {
          i++;
        } else {
          j++;
        }
      }
      hunks.add(
        _Hunk(
          equal: false,
          baselineStart: sI,
          baselineEnd: i,
          currentStart: sJ,
          currentEnd: j,
        ),
      );
    }
  }
  if (i < m || j < n) {
    hunks.add(
      _Hunk(
        equal: false,
        baselineStart: i,
        baselineEnd: m,
        currentStart: j,
        currentEnd: n,
      ),
    );
  }
  return hunks;
}

/// Past de diff toe op original. Voor ongewijzigde regels behouden we de
/// originele regel (byte-getrouw). Voor gewijzigde regels nemen we de nieuwe
/// regel uit current.
///
/// De align-kaart mapt elke baseline-regel naar een original-regel. Voor
/// baseline-regels die de LCS niet kon mappen (verplaatst door de round-trip)
/// zoeken we op inhoud in original — de round-trip verandert regelposities
/// maar niet de tekst van ongewijzigde regels.
String _applyEdits(
  List<String> origLines,
  List<String> baseLines,
  List<String> currLines,
  List<int> align,
  List<_Hunk> hunks,
) {
  // Inhoudskaart voor fallback: regeltekst → ongebruikte posities in original.
  final origByContent = <String, List<int>>{};
  for (var i = 0; i < origLines.length; i++) {
    origByContent.putIfAbsent(origLines[i], () => []).add(i);
  }

  // Originele regels die al via LCS zijn toegewezen — niet hergebruiken.
  final used = <int>{};
  for (final oi in align) {
    if (oi >= 0) used.add(oi);
  }

  // replacement[oi] = regels die origLines[oi] vervangen (leeg = verwijder)
  // insertion[oi] = regels die na origLines[oi] worden ingevoegd
  // insertion[-1] = regels aan het begin
  final replacement = <int, List<String>>{};
  final insertion = <int, List<String>>{};

  for (final h in hunks) {
    if (h.equal) continue;

    final currSlice = currLines.sublist(h.currentStart, h.currentEnd);

    // Zoek originele posities voor de baseline-regels in deze hunk.
    final origIndices = <int>[];
    for (var bi = h.baselineStart; bi < h.baselineEnd; bi++) {
      if (align[bi] >= 0) {
        origIndices.add(align[bi]);
      } else {
        // Fallback: zoek op inhoud in original.
        final line = baseLines[bi];
        final positions = origByContent[line];
        if (positions != null) {
          for (final p in positions) {
            if (!used.contains(p)) {
              used.add(p);
              origIndices.add(p);
              break;
            }
          }
        }
      }
    }

    if (origIndices.isEmpty) {
      // Pure invoeging — plaats vóór de volgende gemapte regel, of aan het eind.
      int? insertAfter;
      for (var bi = h.baselineEnd; bi < baseLines.length; bi++) {
        final target = align[bi] >= 0
            ? align[bi]
            : _findUnused(origByContent, baseLines[bi], used);
        if (target >= 0) {
          insertAfter = target - 1;
          break;
        }
      }
      // Geen volgende gemapte regel → aan het eind. -1 betekent "aan het begin".
      insertAfter ??= origLines.isEmpty ? -1 : origLines.length - 1;
      insertion.putIfAbsent(insertAfter, () => []).addAll(currSlice);
    } else {
      origIndices.sort();
      replacement[origIndices.first] = currSlice;
      for (var i = 1; i < origIndices.length; i++) {
        replacement.putIfAbsent(origIndices[i], () => []);
      }
    }
  }

  // Bouw het resultaat door original te wandelen met vervangingen.
  final result = <String>[];
  if (insertion.containsKey(-1)) result.addAll(insertion[-1]!);
  for (var oi = 0; oi < origLines.length; oi++) {
    if (replacement.containsKey(oi)) {
      result.addAll(replacement[oi]!);
    } else {
      result.add(origLines[oi]);
    }
    if (insertion.containsKey(oi)) result.addAll(insertion[oi]!);
  }
  return result.join('\n');
}

/// Zoekt een ongebruikte positie in original met de gegeven regeltekst.
int _findUnused(
  Map<String, List<int>> origByContent,
  String line,
  Set<int> used,
) {
  final positions = origByContent[line];
  if (positions == null) return -1;
  for (final p in positions) {
    if (!used.contains(p)) return p;
  }
  return -1;
}
