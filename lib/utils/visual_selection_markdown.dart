/// Markdown van een selectie in de visuele editor.
///
/// Quill zet bij knippen alleen de platte tekst op het klembord. Een taaklijst
/// is daar `een\ntwee`: de vinkjes zitten in de regelopmaak, niet in de tekst.
/// Plakken leest dat terug als gewone alinea's, op één regel wanneer de
/// HTML-variant de regeleinden ook nog platslaat (#2398).
library;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import 'markdown_quill_codec.dart';

/// Wat er op het klembord hoort, en welk bereik een knip uit het document haalt.
class VisualClipboardPayload {
  const VisualClipboardPayload({
    required this.start,
    required this.end,
    required this.markdown,
  });

  final int start;

  /// Einde van de te wissen selectie. Ligt voorbij [TextSelection.end] wanneer
  /// de selectie een hele regel beslaat: de regelafsluiter draagt het vinkje,
  /// en die laten staan maakt een lege `- [ ]`-regel.
  final int end;
  final String markdown;
}

/// `null` als er niets te kopiëren valt.
VisualClipboardPayload? visualClipboardPayload(
  Document document,
  int rawStart,
  int rawEnd,
) {
  if (rawStart < 0 || rawEnd < 0) return null;
  final start = rawStart < rawEnd ? rawStart : rawEnd;
  final end = rawStart < rawEnd ? rawEnd : rawStart;
  if (start == end || start >= document.length) return null;
  final safeEnd = end.clamp(start, document.length);
  final atLineStart = _atLineStart(document, start);
  final deleteEnd = atLineStart
      ? _endThroughOwnedLineBreak(document, start, safeEnd)
      : safeEnd;
  final markdown = atLineStart
      ? _markdownOfRange(document, start, deleteEnd)
      : document.getPlainText(start, safeEnd - start);
  final cleaned = markdown.trimRight();
  if (cleaned.isEmpty) return null;
  return VisualClipboardPayload(
    start: start,
    end: deleteEnd,
    markdown: cleaned,
  );
}

bool _atLineStart(Document document, int start) {
  if (start <= 0) return true;
  return document.getPlainText(start - 1, 1) == '\n';
}

/// Neem de regelafsluiter mee wanneer de selectie de hele regeltekst dekt.
int _endThroughOwnedLineBreak(Document document, int start, int end) {
  if (end >= document.length) return document.length;
  final probe = end > 0 ? end - 1 : 0;
  final node = document.queryChild(probe).node;
  if (node is! Line) return end;
  final lineStart = node.documentOffset;
  final lineEnd = lineStart + node.length;
  if (start <= lineStart && end >= lineEnd - 1) {
    return lineEnd.clamp(end, document.length);
  }
  return end;
}

String _markdownOfRange(Document document, int start, int end) {
  var delta = document.toDelta().slice(start, end);
  if (!_endsWithNewline(delta)) {
    final probe = end > start ? end - 1 : start;
    final node = document.queryChild(probe).node;
    final attrs = node is Line ? node.style.toJson() : null;
    delta = delta.concat(Delta()..insert('\n', attrs));
  }
  return MarkdownQuillCodec.markdownFromDocument(Document.fromDelta(delta));
}

bool _endsWithNewline(Delta delta) {
  if (delta.isEmpty) return false;
  final last = delta.last;
  return last.data is String && (last.data as String).endsWith('\n');
}
