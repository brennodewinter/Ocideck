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
  var fenced = false;
  var frontMatter = lines.isNotEmpty && lines.first.trim() == '---';
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (index > 0 && frontMatter && trimmed == '---') {
      frontMatter = false;
      offset += line.length + 1;
      continue;
    }
    if (!frontMatter && RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
    } else if (!frontMatter && !fenced && trimmed == '---') {
      slide++;
    } else if (!frontMatter && !fenced) {
      final heading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$').firstMatch(line);
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
      }
    }
    offset += line.length + 1;
  }
  return entries;
}
