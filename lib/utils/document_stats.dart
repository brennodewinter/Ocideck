/// Document statistics computed from the Markdown body: word count, chapter
/// count (H1), section count (H2+), table count and image count.
///
/// Zuiver Dart — geen Flutter-import, net als `markdown_table_lines.dart`, zodat
/// een test of tooling deze tellers kan aanroepen zonder het materiaal binnen
/// te halen.
library;

import '../models/markdown_outline.dart';
import '../services/markdown_table_lines.dart';

/// Statistieken van een documentbody, geteld op de bron.
class DocumentStats {
  final int words;
  final int chapters;
  final int sections;
  final int tables;
  final int images;

  const DocumentStats({
    required this.words,
    required this.chapters,
    required this.sections,
    required this.tables,
    required this.images,
  });
}

final _reImage = RegExp(r'!\[[^\]]*\]\([^)]+\)');
final _reFence = RegExp(r'^\s*(```|~~~)');
final _reHasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Telt woorden, hoofdstukken (H1), paragrafen (H2+), tabellen en afbeeldingen
/// in [body]. De body is de Markdown zónder stijl-frontmatter.
///
/// Woorden: tokens met minstens één letter of cijfer, buiten fenced code, met
/// afbeeldingsmarkup verwijderd zodat paden niet als woorden meetellen.
/// Afbeeldingen: `![…](…)`-verwijzingen, exclusief `![bg`-achtergronden (Marp).
DocumentStats computeDocumentStats(String body) {
  final outline = buildMarkdownOutline(body);
  var chapters = 0;
  var sections = 0;
  for (final e in outline) {
    if (e.level == 1) {
      chapters++;
    } else {
      sections++;
    }
  }

  final lines = body.split('\n');
  var words = 0;
  var tables = 0;
  var images = 0;
  var fenced = false;
  var inTable = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_reFence.hasMatch(line)) {
      fenced = !fenced;
      inTable = false;
      continue;
    }
    if (fenced) continue;

    // Afbeeldingen (niet `![bg`-achtergronden).
    for (final m in _reImage.allMatches(line)) {
      if (!m.group(0)!.startsWith('![bg')) images++;
    }

    // Tabellen: een blok opent bij een tabelregel + scheidingsrij eronder.
    if (isMarkdownTableLine(line)) {
      if (!inTable) {
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        if (isMarkdownTableDelimiterRow(next)) {
          tables++;
          inTable = true;
        }
      }
    } else {
      inTable = false;
    }

    // Woorden: tokens met een letter of cijfer, zonder afbeeldingsmarkup.
    final cleaned = line.replaceAll(_reImage, ' ');
    for (final token in cleaned.split(RegExp(r'\s+'))) {
      if (token.isNotEmpty && _reHasLetterOrDigit.hasMatch(token)) words++;
    }
  }

  return DocumentStats(
    words: words,
    chapters: chapters,
    sections: sections,
    tables: tables,
    images: images,
  );
}
