/// Kiest uit platte tekst en klembord-HTML welke Markdown de editor invoegt.
///
/// Volgorde: spreadsheet/tabel uit de platte tekst, anders HTML→Markdown,
/// anders opgeschoonde platte tekst. Die volgorde houdt spreadsheet-plakken
/// gelijk aan wat er al was, en vangt het geval waarin de platte tekst de
/// structuur al heeft verloren (#1595).
///
/// Uitzondering: een platte taak- of opsomlijst die de HTML tot één regel of
/// tot een lijst zonder vinkjes platslaat, blijft de platte tekst. Het
/// klembord van de visuele editor zet de Markdown er zelf op; HTML van een
/// eerdere kopie mag die niet overschrijven (#2398).
library;

import 'html_to_markdown.dart';
import 'markdown_paste_cleanup.dart';
import 'table_clipboard.dart';

/// Hoe [resolveClipboardMarkdown] de tekst heeft verkregen.
enum ClipboardMarkdownKind {
  /// GFM-tabel uit TSV/CSV/pijpen in de platte-tekstvariant.
  table,

  /// Gewone Markdown (uit HTML of uit opgeschoonde platte tekst).
  markdown,
}

/// Uitkomst van [resolveClipboardMarkdown].
class ClipboardMarkdown {
  const ClipboardMarkdown(this.text, this.kind);

  final String text;
  final ClipboardMarkdownKind kind;
}

/// Bepaalt wat er na een plak in de bron hoort te staan.
///
/// `null` als beide varianten leeg zijn of niets bruikbaars opleveren.
ClipboardMarkdown? resolveClipboardMarkdown({String? plain, String? html}) {
  if (plain != null && plain.isNotEmpty) {
    final table = parseClipboardTable(plain);
    if (table != null && table.isNotEmpty) {
      return ClipboardMarkdown(
        _encodeGfmTable(table),
        ClipboardMarkdownKind.table,
      );
    }
  }
  if (html != null && html.isNotEmpty) {
    final fromHtml = htmlClipboardToMarkdown(html);
    if (fromHtml != null && fromHtml.isNotEmpty) {
      if (plain != null && _plainKeepsListStructure(plain, fromHtml)) {
        final cleaned = sanitizeMarkdownPaste(plain);
        if (cleaned.isNotEmpty) {
          return ClipboardMarkdown(cleaned, ClipboardMarkdownKind.markdown);
        }
      }
      return ClipboardMarkdown(fromHtml, ClipboardMarkdownKind.markdown);
    }
  }
  if (plain == null || plain.isEmpty) return null;
  final cleaned = sanitizeMarkdownPaste(plain);
  if (cleaned.isEmpty) return null;
  return ClipboardMarkdown(cleaned, ClipboardMarkdownKind.markdown);
}

final _taskLine = RegExp(r'^\s*[-*+] \[[ xX]\] ', multiLine: true);
final _listLine = RegExp(
  r'^\s*(?:[-*+] \[[ xX]\] |[-*+] |\d+\. )',
  multiLine: true,
);

/// De platte tekst bewaart een lijst die de HTML-variant verliest.
///
/// Twee gevallen: de vinkjes staan alleen in de platte tekst, of de HTML
/// vouwt meerdere lijstregels tot minder regels op. Een HTML-variant die
/// evenveel lijstregels houdt — inclusief een diepere nesteling — wint nog
/// steeds, want dáár zit de structuur die de platte tekst kwijt is (#1595).
bool _plainKeepsListStructure(String plain, String fromHtml) {
  if (_taskLine.hasMatch(plain) && !_taskLine.hasMatch(fromHtml)) return true;
  final plainLists = _listLine.allMatches(plain).length;
  final htmlLists = _listLine.allMatches(fromHtml).length;
  return plainLists >= 2 && htmlLists < plainLists;
}

/// Minimale GFM-tabel, dezelfde pijp-ontsnapping als de rest van de app.
String _encodeGfmTable(List<List<String>> rows) {
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String cell(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll('<br>', r'\<br>')
      .replaceAll('\n', '<br>');
  String line(List<String> r) =>
      '| ${List.generate(cols, (c) => cell(c < r.length ? r[c] : '')).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(cols, '---').join(' | ')} |',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}
