import 'package:xml/xml.dart';

import '../../models/source_table.dart';
import 'pptx_context.dart';

/// Salvage a DrawingML table (`a:tbl`) into a [SourceTable].
///
/// The first row is the header; every `a:tc` cell's text is concatenated from
/// its `a:txBody` paragraphs. Merged cells (`gridSpan`/`rowSpan`) are
/// flattened — OciDeck tables have no spans, so a merge is recorded as a
/// conversion issue by the pipeline, not here.
SourceTable? parseTableXml(XmlElement tbl) {
  final rows = <List<String>>[];
  for (final tr in descendantsLocal(tbl, 'tr')) {
    final cells = <String>[];
    for (final tc in descendantsLocal(tr, 'tc')) {
      cells.add(_cellText(tc));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return null;

  final header = rows.first;
  final body = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];
  return SourceTable(header: header, rows: body);
}

String _cellText(XmlElement tc) {
  final txBody = descendantsLocal(tc, 'txBody').firstOrNull;
  if (txBody == null) return '';
  final parts = <String>[];
  for (final p in descendantsLocal(txBody, 'p')) {
    final text = descendantsLocal(p, 't').map((e) => e.innerText).join().trim();
    if (text.isNotEmpty) parts.add(text);
  }
  return parts.join('\n');
}
