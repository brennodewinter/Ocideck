class MarkdownOutlineEntry {
  final int line;
  final int offset;
  final int slideNumber;
  final int level;
  final String title;

  const MarkdownOutlineEntry({
    required this.line,
    required this.offset,
    required this.slideNumber,
    required this.level,
    required this.title,
  });
}

/// Builds a source outline without normalising or reparsing the document.
/// Headings inside fenced code and YAML front matter are deliberately ignored.
List<MarkdownOutlineEntry> buildMarkdownOutline(String markdown) {
  final entries = <MarkdownOutlineEntry>[];
  final lines = markdown.split('\n');
  var offset = 0;
  var slide = 1;
  String? fence;
  var fenceLength = 0;
  var skipSetext = false;
  var frontMatter = lines.isNotEmpty && lines.first.trim() == '---';
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (index > 0 && frontMatter && trimmed == '---') {
      frontMatter = false;
      offset += line.length + 1;
      continue;
    }
    if (skipSetext) {
      skipSetext = false;
      offset += line.length + 1;
      continue;
    }
    final delimiter = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (!frontMatter && delimiter != null) {
      final marks = delimiter.group(1)!;
      if (fence == null) {
        fence = marks[0];
        fenceLength = marks.length;
      } else if (marks[0] == fence &&
          marks.length >= fenceLength &&
          delimiter.group(2)!.trim().isEmpty) {
        fence = null;
      }
    } else if (!frontMatter && fence == null && trimmed == '---') {
      slide++;
    } else if (!frontMatter && fence == null) {
      final heading = RegExp(
        r'^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$',
      ).firstMatch(line);
      if (heading != null) {
        entries.add(
          MarkdownOutlineEntry(
            line: index + 1,
            offset: offset,
            slideNumber: slide,
            level: heading.group(1)!.length,
            title: heading.group(2)!,
          ),
        );
      } else if (trimmed.isNotEmpty &&
          index + 1 < lines.length &&
          RegExp(r'^ {0,3}(=+|-+)\s*$').hasMatch(lines[index + 1]) &&
          !RegExp(r'^ {4}|^\s*[-*>#]').hasMatch(line)) {
        entries.add(
          MarkdownOutlineEntry(
            line: index + 1,
            offset: offset,
            slideNumber: slide,
            level: lines[index + 1].trimLeft().startsWith('=') ? 1 : 2,
            title: trimmed,
          ),
        );
        skipSetext = true;
      }
    }
    offset += line.length + 1;
  }
  return entries;
}

/// De kop waaronder [offset] in de markdownbron valt, als index in [outline],
/// of `-1` boven de eerste kop. De koppen staan op bronvolgorde, dus de laatste
/// kop die vóór de cursor begint wint.
int activeOutlineIndexForOffset(
  List<MarkdownOutlineEntry> outline,
  int offset,
) {
  var active = -1;
  for (var i = 0; i < outline.length; i++) {
    if (outline[i].offset > offset) break;
    active = i;
  }
  return active;
}

/// Hetzelfde, maar gemeten in de plátte tekst van de visuele editor: daar zijn
/// de bron-offsets onbruikbaar (de opmaaktekens staan er niet meer in), dus de
/// koppen worden op titel teruggezocht — elke volgende vanaf waar de vorige
/// eindigde, zodat twee gelijknamige koppen niet allebei op de eerste treffer
/// uitkomen. Een kop die niet in de platte tekst te vinden is, wordt
/// overgeslagen in plaats van de rest te blokkeren.
int activeOutlineIndexInPlainText(
  List<MarkdownOutlineEntry> outline,
  String plain,
  int caret,
) {
  var active = -1;
  var searchFrom = 0;
  for (var i = 0; i < outline.length; i++) {
    final at = plain.indexOf(outline[i].title, searchFrom);
    if (at < 0) continue;
    if (at > caret) break;
    active = i;
    searchFrom = at + outline[i].title.length;
  }
  return active;
}
