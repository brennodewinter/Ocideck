import 'markdown_outline.dart';

class MarkdownSourceBlock {
  final String id;
  final int slideNumber;
  final int start;
  final int end;
  final String anchor;

  const MarkdownSourceBlock({
    required this.id,
    required this.slideNumber,
    required this.start,
    required this.end,
    required this.anchor,
  });

  String textIn(String source) => source.substring(start, end);
}

/// Lossless source document: structural ranges point into the exact original
/// string. Parsing never normalises whitespace, escapes, directives or unknown
/// Markdown, and block edits replace only the selected source range.
class MarkdownSourceDocument {
  final String source;
  final List<MarkdownSourceBlock> blocks;
  final List<MarkdownOutlineEntry> outline;
  final int _nextId;

  const MarkdownSourceDocument._({
    required this.source,
    required this.blocks,
    required this.outline,
    required this._nextId,
  });

  factory MarkdownSourceDocument.parse(
    String source, {
    MarkdownSourceDocument? previous,
  }) {
    final ranges = _slideRanges(source);
    final outline = buildMarkdownOutline(source);
    final anchors = <String>[
      for (var index = 0; index < ranges.length; index++)
        _anchorFor(source, ranges[index], outline, index + 1),
    ];
    final ids = List<String?>.filled(ranges.length, null);
    final usedPrevious = <int>{};
    var nextId = previous?._nextId ?? 1;

    if (previous != null) {
      for (var index = 0; index < anchors.length; index++) {
        final anchor = anchors[index];
        if (anchor.isEmpty) continue;
        final matches = <int>[
          for (var old = 0; old < previous.blocks.length; old++)
            if (!usedPrevious.contains(old) &&
                previous.blocks[old].anchor == anchor)
              old,
        ];
        if (matches.length == 1) {
          ids[index] = previous.blocks[matches.single].id;
          usedPrevious.add(matches.single);
        }
      }
      // A changed slide normally keeps its position between unchanged
      // neighbours. Reuse the nearest remaining identity before minting one.
      for (var index = 0; index < ids.length; index++) {
        if (ids[index] != null) continue;
        int? nearest;
        var distance = 1 << 30;
        for (var old = 0; old < previous.blocks.length; old++) {
          if (usedPrevious.contains(old)) continue;
          final candidateDistance = (old - index).abs();
          if (candidateDistance < distance) {
            nearest = old;
            distance = candidateDistance;
          }
        }
        if (nearest != null && distance <= 1) {
          ids[index] = previous.blocks[nearest].id;
          usedPrevious.add(nearest);
        }
      }
    }

    final blocks = <MarkdownSourceBlock>[];
    for (var index = 0; index < ranges.length; index++) {
      final id = ids[index] ?? 'source-slide-${nextId++}';
      blocks.add(
        MarkdownSourceBlock(
          id: id,
          slideNumber: index + 1,
          start: ranges[index].$1,
          end: ranges[index].$2,
          anchor: anchors[index],
        ),
      );
    }
    return MarkdownSourceDocument._(
      source: source,
      blocks: List.unmodifiable(blocks),
      outline: List.unmodifiable(outline),
      nextId: nextId,
    );
  }

  MarkdownSourceDocument reparse(String nextSource) =>
      MarkdownSourceDocument.parse(nextSource, previous: this);

  MarkdownSourceBlock? blockAt(int offset) {
    if (blocks.isEmpty) return null;
    final safe = offset.clamp(0, source.length);
    if (safe < blocks.first.start) return blocks.first;
    for (final block in blocks) {
      if (safe >= block.start && safe <= block.end) return block;
    }
    return blocks.last;
  }

  MarkdownSourceDocument replaceBlock(String id, String replacement) {
    MarkdownSourceBlock? block;
    for (final candidate in blocks) {
      if (candidate.id == id) {
        block = candidate;
        break;
      }
    }
    if (block == null) return this;
    final updated = source.replaceRange(block.start, block.end, replacement);
    return reparse(updated);
  }
}

List<(int, int)> _slideRanges(String source) {
  if (source.isEmpty) return const [(0, 0)];
  final ranges = <(int, int)>[];
  final lines = source.split('\n');
  var offset = 0;
  var blockStart = 0;
  var fenced = false;
  var frontMatter = lines.first.trim() == '---';
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    final lineEnd = offset + line.length;
    if (index > 0 && frontMatter && trimmed == '---') {
      frontMatter = false;
      blockStart = lineEnd < source.length ? lineEnd + 1 : lineEnd;
    } else if (!frontMatter && RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
    } else if (!frontMatter && !fenced && trimmed == '---') {
      ranges.add((blockStart, offset));
      blockStart = lineEnd < source.length ? lineEnd + 1 : lineEnd;
    }
    offset = lineEnd + 1;
  }
  ranges.add((blockStart, source.length));
  return ranges;
}

String _anchorFor(
  String source,
  (int, int) range,
  List<MarkdownOutlineEntry> outline,
  int slideNumber,
) {
  final headings = outline.where((entry) => entry.slideNumber == slideNumber);
  if (headings.isNotEmpty) return 'h:${headings.first.title.trim()}';
  for (final line in source.substring(range.$1, range.$2).split('\n')) {
    final value = line.trim();
    if (value.isNotEmpty && value != '---' && !value.startsWith('<!--')) {
      return 't:${value.length > 80 ? value.substring(0, 80) : value}';
    }
  }
  return '';
}
