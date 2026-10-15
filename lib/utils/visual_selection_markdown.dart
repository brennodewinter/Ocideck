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
      : _markdownFromMidLine(document, start, safeEnd);
  final cleaned = markdown.trimRight();
  if (cleaned.isEmpty) return null;
  return VisualClipboardPayload(
    start: start,
    end: deleteEnd,
    markdown: cleaned,
  );
}

/// Een selectie die midden in een regel begint (#2439). Het begin ervan is
/// een tekstfragment: een deel van een lijstitem is geen lijstitem. Alles
/// vanaf de volgende regel is wél hele regels en gaat met zijn eigen
/// blokopmaak mee — anders verdwijnen bullets, nummering en vinkjes van elk
/// volledig geselecteerd item, want platte tekst kent ze niet.
String _markdownFromMidLine(Document document, int start, int end) {
  final first = document.queryChild(start).node;
  if (first is! Line) return document.getPlainText(start, end - start);
  // Positie van de regelafsluiter van de eerste regel.
  final firstLineBreak = first.documentOffset + first.length - 1;
  if (end <= firstLineBreak) {
    return document.getPlainText(start, end - start);
  }
  final head = document.getPlainText(start, firstLineBreak - start);
  final tailStart = firstLineBreak + 1;
  // De selectie eindigt precies achter het regeleinde: er valt niets meer te
  // serialiseren. Zonder deze stop kreeg de ónderliggende regel een leeg
  // lijstitem, omdat de afsluiter ontbrak en die met haar opmaak werd aangevuld.
  if (end <= tailStart) return head;
  final tail = _markdownOfRange(document, tailStart, end);
  if (head.trim().isEmpty) return tail;
  // Een lege regel ertussen: een genummerde lijst die niet met 1 begint kan in
  // Markdown geen alinea onderbreken en zou aan het fragment vastplakken.
  return '$head\n\n$tail';
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
  return _clampListFragmentIndent(
    MarkdownQuillCodec.markdownFromDocument(Document.fromDelta(delta)),
  );
}

final _listLine = RegExp(r'^( *)(?:[-*+]|\d+[.)])(?: |$)');

/// Een selectie die midden in een geneste lijst begint, levert een eerste
/// item dat nog zijn oorspronkelijke inspringing draagt. Vier spaties vooraan
/// leest Markdown als codeblok en het kopieerresultaat verliest zijn lijst
/// (#2439). Een lijstfragment begint op niveau 0, en geen item ligt meer dan
/// één niveau dieper dan het vorige: dat is wat Markdown als lijst herkent.
String _clampListFragmentIndent(String markdown) {
  final lines = markdown.split('\n');
  final first = _listLine.firstMatch(lines.first);
  if (first == null || first.group(1)!.isEmpty) return markdown;
  const unit = 4;
  var previous = -1;
  for (var i = 0; i < lines.length; i++) {
    final m = _listLine.firstMatch(lines[i]);
    if (m == null) continue;
    final level = m.group(1)!.length ~/ unit;
    final clamped = level.clamp(0, previous + 1);
    previous = clamped;
    if (clamped != level) {
      lines[i] =
          ' ' * (clamped * unit) + lines[i].substring(m.group(1)!.length);
    }
  }
  return lines.join('\n');
}

bool _endsWithNewline(Delta delta) {
  if (delta.isEmpty) return false;
  final last = delta.last;
  return last.data is String && (last.data as String).endsWith('\n');
}
