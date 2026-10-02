// Gedeelde spreadsheet→Markdown-opbouw voor de headless sheet-importeurs
// (CSV, XLSX, ODS): een werkblad is hier alleen nog een naam met een rooster
// van platte celteksten. De formaatspecifieke parsers leveren [SheetGrid]s;
// dit bestand trimt, ontsnapt en schrijft ze als koppen plus GFM-tabellen.
//
// Waarom dit gedeeld is en niet drie keer staat: de Markdown-vorm (titel als
// H1, bladnaam als H2, eerste rij als tabelkop) is één uitwerpbeslissing die
// voor elk bronformaat hetzelfde moet zijn.
library;

import 'document_markdown.dart';

/// Eén werkblad als los rooster: [name] is de bladnaam uit de bron (leeg bij
/// CSV, dat geen bladen kent), [rows] de cellen als platte tekst per rij.
typedef SheetGrid = ({String name, List<List<String>> rows});

/// Zet [title] plus de [sheets] om in platte Markdown: `# titel`, per blad een
/// `## bladnaam` (alleen als die een naam heeft) en de tabel eronder.
///
/// Een blad zonder enige niet-lege cel valt weg — een kop boven niets zegt
/// minder dan de afwezigheid ervan. Bladvormende whitespace blijft wél
/// binnen het rooster staan zolang die cellen tussen gevulde rijen zitten.
String spreadsheetToMarkdown(String title, List<SheetGrid> sheets) {
  final buf = StringBuffer();
  if (title.isNotEmpty) {
    buf
      ..writeln('# ${escapeDocumentMarkdown(title)}')
      ..writeln();
  }
  for (final sheet in sheets) {
    final rows = _trimmed(sheet.rows);
    if (rows.isEmpty) continue;
    if (sheet.name.isNotEmpty) {
      buf
        ..writeln('## ${escapeDocumentMarkdown(sheet.name)}')
        ..writeln();
    }
    writeDocumentMarkdownTable(buf, [
      for (final row in rows) [for (final c in row) escapeDocumentMarkdown(c)],
    ]);
    buf.writeln();
  }
  return finishDocumentMarkdown(buf.toString());
}

/// Snijdt lege rijen en kolommen van de randen af en brengt elke rij op de
/// breedte van de breedste — GFM verlangt een rechthoek.
List<List<String>> _trimmed(List<List<String>> rows) {
  var end = rows.length;
  while (end > 0 && rows[end - 1].every((c) => c.trim().isEmpty)) {
    end--;
  }
  var start = 0;
  while (start < end && rows[start].every((c) => c.trim().isEmpty)) {
    start++;
  }
  if (start >= end) return const [];

  final used = rows.sublist(start, end);
  var width = 0;
  for (final row in used) {
    var last = row.length;
    while (last > 0 && row[last - 1].trim().isEmpty) {
      last--;
    }
    if (last > width) width = last;
  }
  return [
    for (final row in used)
      [for (var i = 0; i < width; i++) i < row.length ? row[i].trim() : ''],
  ];
}
