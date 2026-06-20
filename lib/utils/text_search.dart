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
List<TextMatchRange> findAllMatches(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];

  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TextMatchRange>[];
  var start = 0;
  while (true) {
    final index = haystack.indexOf(needle, start);
    if (index < 0) break;
    matches.add(TextMatchRange(index, index + query.length));
    start = index + query.length;
  }
  return matches;
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
}) {
  if (query.isEmpty) return (text: text, count: 0);

  final matches = findAllMatches(text, query, caseSensitive: caseSensitive);
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
