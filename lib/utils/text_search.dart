/// A character range within a string (start inclusive, end exclusive).
class TextMatchRange {
  final int start;
  final int end;

  const TextMatchRange(this.start, this.end);

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is TextMatchRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Finds all non-overlapping occurrences of [query] in [text].
///
/// [protectedRanges] markeert delen die niet meetellen: een treffer die zo'n
/// deel ook maar raakt telt niet mee. Zoekt u op Markdown-bron, gebruik dan
/// [markdownNonTextRanges] — machinesyntax is geen proza (#2137).
List<TextMatchRange> findAllMatches(
  String text,
  String query, {
  bool caseSensitive = false,
  List<TextMatchRange> protectedRanges = const [],
}) {
  if (query.isEmpty) return const [];

  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final protected = protectedRanges.isEmpty
      ? const <TextMatchRange>[]
      : (List.of(protectedRanges)
          ..sort((left, right) => left.start.compareTo(right.start)));
  final matches = <TextMatchRange>[];
  var start = 0;
  var protectedCursor = 0;
  while (true) {
    final index = haystack.indexOf(needle, start);
    if (index < 0) break;
    final end = index + query.length;
    // De bereiken liggen op volgorde; schuif door tot degene die deze
    // treffer nog zou kunnen overlappen.
    while (protectedCursor < protected.length &&
        protected[protectedCursor].end <= index) {
      protectedCursor++;
    }
    if (protectedCursor < protected.length &&
        protected[protectedCursor].start < end) {
      // Raakt beschermde syntax — overslaan, maar vanaf het volgende teken
      // verder zoeken (de volgende treffer kan er deels onder liggen).
      start = index + 1;
      continue;
    }
    matches.add(TextMatchRange(index, end));
    start = end;
  }
  return matches;
}

final _fenceRe = RegExp(r'^\s*(```|~~~)');
final _inlineLinkRe = RegExp(r'!?\[[^\]\n]*\]\([^\)\n]*\)');
final _refLinkRe = RegExp(r'!?\[[^\]\n]*\]\[[^\]\n]*\]');
final _footnoteRe = RegExp(r'\[\^[^\]\n]*\]');
final _refDefRe = RegExp(r'^\s*\[(?!\^)[^\]\n]+\]\s*:');

/// Welke delen van Markdown-bron níet als tekst renderen: het zoeken en
/// vervangen slaat ze over, want een herschreven linkdoel of comment is
/// dataverlies in het klein (#2137).
///
/// Gemaskeerd worden: fenced codeblokken (inclusief ```chart- en
/// ```mermaid-specs), HTML-comments (meerregelig meegerekend — daarin zitten
/// ook de sprekersnotities van een deck), links en afbeeldingen in hun
/// geheel (het label telt net zo min mee als het doel), `[^…]`-voetnoot-
/// markeringen, en `[sleutel]: doel`-verwijzingsdefinities. Platte proza —
/// inclusief kopteksten, tabelcellen en voetnootteksten — blijft zoekbaar.
List<TextMatchRange> markdownNonTextRanges(String source) {
  final ranges = <TextMatchRange>[];
  final lines = source.split('\n');
  var offset = 0;
  var fenced = false;
  int? commentStart;
  for (final line in lines) {
    final end = offset + line.length;
    if (commentStart == null && _fenceRe.hasMatch(line)) {
      fenced = !fenced;
      ranges.add(TextMatchRange(offset, end));
    } else if (fenced || _refDefRe.hasMatch(line)) {
      ranges.add(TextMatchRange(offset, end));
    } else {
      var pos = 0;
      while (pos < line.length) {
        if (commentStart != null) {
          final close = line.indexOf('-->', pos);
          if (close < 0) break;
          ranges.add(TextMatchRange(commentStart, offset + close + 3));
          commentStart = null;
          pos = close + 3;
          continue;
        }
        final open = line.indexOf('<!--', pos);
        final upto = open < 0 ? line.length : open;
        _maskInlineSyntax(line, pos, upto, offset, ranges);
        if (open < 0) break;
        commentStart = offset + open;
        pos = open + 4;
      }
      // Een comment die op deze of een eerdere regel opende en hier niet
      // sluit, maskeert tot het regel-einde; de staart komt bij een volgende
      // regel (of aan het einde van de bron) erbij.
      if (commentStart != null) ranges.add(TextMatchRange(commentStart, end));
    }
    offset = end + 1;
  }
  if (commentStart != null) {
    ranges.add(TextMatchRange(commentStart, source.length));
  }
  return ranges;
}

/// De machinesyntax op het proza-deel [from]–[to] van [line]: links,
/// afbeeldingen, verwijzingslinks en voetnootmarkeringen.
void _maskInlineSyntax(
  String line,
  int from,
  int to,
  int base,
  List<TextMatchRange> out,
) {
  if (from >= to) return;
  final segment = line.substring(from, to);
  for (final re in [_inlineLinkRe, _refLinkRe, _footnoteRe]) {
    for (final match in re.allMatches(segment)) {
      out.add(TextMatchRange(base + from + match.start, base + from + match.end));
    }
  }
}

/// Returns the next match index, wrapping to 0 when [wrap] is true.
int nextMatchIndex(int current, int count, {bool wrap = true}) {
  if (count <= 0) return -1;
  if (current < 0) return 0;
  final next = current + 1;
  if (next < count) return next;
  return wrap ? 0 : current;
}

/// Returns the previous match index, wrapping to [count - 1] when [wrap] is true.
int previousMatchIndex(int current, int count, {bool wrap = true}) {
  if (count <= 0) return -1;
  if (current < 0) return count - 1;
  final prev = current - 1;
  if (prev >= 0) return prev;
  return wrap ? count - 1 : current;
}

/// Replaces [range] in [text] with [replacement].
String replaceRange(String text, TextMatchRange range, String replacement) {
  return text.replaceRange(range.start, range.end, replacement);
}

/// Replaces all occurrences of [query] in [text] and returns the result plus
/// the number of replacements made.
({String text, int count}) replaceAllInText(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = false,
  List<TextMatchRange> protectedRanges = const [],
}) {
  if (query.isEmpty) return (text: text, count: 0);

  final matches = findAllMatches(
    text,
    query,
    caseSensitive: caseSensitive,
    protectedRanges: protectedRanges,
  );
  if (matches.isEmpty) return (text: text, count: 0);

  final buffer = StringBuffer();
  var lastEnd = 0;
  for (final match in matches) {
    buffer.write(text.substring(lastEnd, match.start));
    buffer.write(replacement);
    lastEnd = match.end;
  }
  buffer.write(text.substring(lastEnd));
  return (text: buffer.toString(), count: matches.length);
}
