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
///
/// CRLF-documenten: de originele bron kan `\r\n`-regeleinden hebben, terwijl
/// Quill naar `\n` normaliseert. De vergelijking stroopt `\r` af; de uitvoer
/// gebruikt het oorspronkelijke scheidingsteken (#1648).
String patchVisualEdits({
  required String original,
  required String baseline,
  required String current,
}) {
  if (baseline == current) return original;

  // CRLF-bewaring: onthoud het originele scheidingsteken (#1648).
  final isCrlf = original.contains('\r\n');
  final sep = isCrlf ? '\r\n' : '\n';

  // Stroop \r van regeleinden voor vergelijking — Quill normaliseert naar LF.
  final origLines = original.split('\n').map(_stripCr).toList();
  final baseLines = baseline.split('\n');
  final currLines = current.split('\n');

  // Stap 1: mappen baseline-regel → original-regel via LCS.
  final align = _alignLines(origLines, baseLines);

  // Stap 2: diff baseline → current (gebruikersbewerkingen).
  final hunks = _lcsDiff(baseLines, currLines);

  // Stap 3: bouw het resultaat op basis van original, met bewerkingen
  // toegepast op de overeenkomende posities.
  return _applyEdits(origLines, baseLines, currLines, align, hunks).join(sep);
}

/// Verwijdert een achterblijvende `\r` van een regel na `split('\n')`.
String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

/// Maximumdimensie van de LCS-kern. Boven deze grens valt de matcher terug
/// op positie-afhankelijke matching — geen volledige matrix.
/// ponytail: ceiling 2000×2000 = 16 MiB int-matrix; boven deze grens is
/// positie-match voldoende omdat visuele bewerkingen lokaal zijn.
const _lcsMaxDim = 2000;

/// Trimt de gemeenschappelijke prefix en suffix van twee lijsten. Retourneert
/// (aStart, aEnd, bStart, bEnd) voor het differing middenstuk.
({int aStart, int aEnd, int bStart, int bEnd}) _trimCommon(
  List<String> a,
  List<String> b,
) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var aEnd = a.length;
  var bEnd = b.length;
  while (aEnd > start && bEnd > start && a[aEnd - 1] == b[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  return (aStart: start, aEnd: aEnd, bStart: start, bEnd: bEnd);
}

/// Mapt elke regel in [b] naar de overeenkomende regel in [a] via LCS.
/// Retourneert een lijst waar index i de index in [a] geeft voor b[i],
/// of -1 als er geen overeenkomst is.
///
/// Trimt eerst gemeenschappelijke prefix/suffix, zodat de LCS-matrix alleen
/// het differing middenstuk dekt — bij een kleine bewerking in een lang
/// document is dat middenstuk klein, en schaalt de matcher lineair in plaats
/// van kwadratisch (#1651).
List<int> _alignLines(List<String> a, List<String> b) {
  final align = List<int>.filled(b.length, -1);

  // Prefix: identieke regels aan het begin matchen 1-op-1.
  final core = _trimCommon(a, b);
  for (var i = 0; i < core.aStart; i++) {
    align[i] = i;
  }
  // Suffix: identieke regels aan het eind matchen verschoven.
  for (var i = 0; i < a.length - core.aEnd; i++) {
    align[core.bEnd + i] = core.aEnd + i;
  }

  // Kern: LCS op het middenstuk, tenzij het te groot is.
  final aCore = a.sublist(core.aStart, core.aEnd);
  final bCore = b.sublist(core.bStart, core.bEnd);
  if (aCore.isEmpty || bCore.isEmpty) return align;
  if (aCore.length > _lcsMaxDim || bCore.length > _lcsMaxDim) {
    _positionalMatch(aCore, bCore, core.aStart, core.bStart, align);
    return align;
  }

  final coreAlign = _lcsAlign(aCore, bCore);
  for (var j = 0; j < bCore.length; j++) {
    if (coreAlign[j] >= 0) {
      align[core.bStart + j] = core.aStart + coreAlign[j];
    }
  }
  return align;
}

/// Volledige LCS-uitlijning op twee lijsten.
List<int> _lcsAlign(List<String> a, List<String> b) {
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
    } else if (dp[i + 1][j] > dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return align;
}

/// Terugval voor te grote lijsten: match regels op positie wanneer ze gelijk
/// zijn, anders geen match. Voldoende voor lokale bewerkingen in lange
/// documenten — de prefix/suffix-trimming heeft het gemeenschappelijke deel
/// al afgedekt.
void _positionalMatch(
  List<String> a,
  List<String> b,
  int aOffset,
  int bOffset,
  List<int> align,
) {
  for (var j = 0; j < b.length; j++) {
    if (j < a.length && a[j] == b[j]) {
      align[bOffset + j] = aOffset + j;
    }
  }
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
///
/// Trimt eerst gemeenschappelijke prefix/suffix (#1651): bij een kleine
/// bewerking is alleen het middenstuk verschillend, en de LCS-matrix dekt
/// alleen dat stuk.
List<_Hunk> _lcsDiff(List<String> a, List<String> b) {
  final core = _trimCommon(a, b);
  final hunks = <_Hunk>[];

  // Prefix als equal-hunk.
  if (core.aStart > 0) {
    hunks.add(
      _Hunk(
        equal: true,
        baselineStart: 0,
        baselineEnd: core.aStart,
        currentStart: 0,
        currentEnd: core.bStart,
      ),
    );
  }

  // Kern: LCS op het middenstuk.
  final aCore = a.sublist(core.aStart, core.aEnd);
  final bCore = b.sublist(core.bStart, core.bEnd);
  if (aCore.isNotEmpty || bCore.isNotEmpty) {
    if (aCore.length > _lcsMaxDim || bCore.length > _lcsMaxDim) {
      // Te groot voor volledige LCS: behandel als één grote change-hunk.
      hunks.add(
        _Hunk(
          equal: false,
          baselineStart: core.aStart,
          baselineEnd: core.aEnd,
          currentStart: core.bStart,
          currentEnd: core.bEnd,
        ),
      );
    } else {
      final coreHunks = _lcsHunks(aCore, bCore);
      for (final h in coreHunks) {
        hunks.add(
          _Hunk(
            equal: h.equal,
            baselineStart: h.baselineStart + core.aStart,
            baselineEnd: h.baselineEnd + core.aStart,
            currentStart: h.currentStart + core.bStart,
            currentEnd: h.currentEnd + core.bStart,
          ),
        );
      }
    }
  }

  // Suffix als equal-hunk.
  if (core.aEnd < a.length) {
    hunks.add(
      _Hunk(
        equal: true,
        baselineStart: core.aEnd,
        baselineEnd: a.length,
        currentStart: core.bEnd,
        currentEnd: b.length,
      ),
    );
  }

  return hunks;
}

/// Volledige LCS-hunks op twee lijsten.
List<_Hunk> _lcsHunks(List<String> a, List<String> b) {
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
        if (dp[i + 1][j] > dp[i][j + 1]) {
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
List<String> _applyEdits(
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
  return result;
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
