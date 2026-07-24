import 'package:xml/xml.dart';

import '../../models/source_table.dart';
import 'odp_context.dart';

/// Salvage an ODF `<table:table>` into a [SourceTable].
///
/// The first row is the header (ODP does not mark it explicitly); every
/// `<table:table-cell>` contributes its paragraph text joined by newlines.
/// Cells with `table:number-columns-repeated` are expanded so columns line up
/// (a common ODF space-saving trick for empty cells).
SourceTable? parseOdpTable(XmlElement tbl) {
  final rows = <List<String>>[];
  for (final tr in childrenLocal(tbl, 'table-row')) {
    final cells = <String>[];
    for (final tc in childrenLocal(tr, 'table-cell')) {
      final repeat =
          int.tryParse(_attr(tc, 'number-columns-repeated') ?? '') ?? 1;
      final text = _cellText(tc);
      for (var i = 0; i < repeat; i++) {
        cells.add(text);
      }
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return null;

  final header = rows.first;
  final body = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];
  return SourceTable(header: header, rows: body);
}

String _cellText(XmlElement cell) {
  final parts = <String>[];
  for (final p in descendantsLocal(cell, 'p')) {
    final t = _innerText(p).trim();
    if (t.isNotEmpty) parts.add(t);
  }
  return parts.join('\n');
}

String _innerText(XmlElement el) {
  final buf = StringBuffer();
  for (final node in el.descendants) {
    if (node is XmlText) buf.write(node.value);
  }
  return buf.toString();
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
