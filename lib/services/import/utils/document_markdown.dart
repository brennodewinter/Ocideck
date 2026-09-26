/// Gedeelde Markdown-opbouw voor de headless DOCX- en ODT-importeurs.
library;

/// Ontsnapt Markdown-magische tekens in platte documenttekst.
String escapeDocumentMarkdown(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll('`', '\\`')
    .replaceAll('#', '\\#')
    .replaceAll('|', '\\|');

/// Schrijft reeds als inline-Markdown opgebouwde cellen als één GFM-tabel.
///
/// Een harde regeleinde binnen een Office-cel mag geen nieuwe Markdown-rij
/// beginnen. De inline-opbouw heeft pijpen en backslashes dan al ontsnapt;
/// alleen die regeleinden worden hier daarom naar `<br>` gevouwen.
void writeDocumentMarkdownTable(StringBuffer buffer, List<List<String>> rows) {
  if (rows.isEmpty) return;

  String line(List<String> cells) =>
      '| ${cells.map(_singleLineTableCell).join(' | ')} |';
  buffer.writeln(line(rows.first));
  buffer.writeln('| ${rows.first.map((_) => '---').join(' | ')} |');
  for (final row in rows.skip(1)) {
    buffer.writeln(line(row));
  }
}

String _singleLineTableCell(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\n', '<br>');

/// Verwijdert lege slotregels en eindigt niet-lege Markdown met één newline.
String finishDocumentMarkdown(String value) {
  var result = value.trimRight();
  if (result.isNotEmpty) result += '\n';
  return result;
}
