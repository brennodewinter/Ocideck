/// De regelherkenning van een Markdown-tabel: welke regel is een tabelregel, en
/// welke is de scheidingsrij eronder. Plus het splitsen van één regel in cellen,
/// waar de scheidingsrij op leunt.
///
/// **Waarom dit los staat van [markdown_table_codec.dart].** Die module
/// importeert `models/slide.dart` voor `TableAlign`, en dat sleept via
/// `improvement/canvas_spec.dart` → `l10n/app_localizations.dart` het hele
/// Flutter-materiaal mee. Een parser die zichzelf zuiver noemt, kan die import
/// dus niet doen — en de tabelpredicaten zijn precies wat zo'n parser nodig
/// heeft om een gemarkeerde tabel te herkennen zonder hem te decoderen.
///
/// Deze bestandsscheiding is de import, niet de betekenis: `markdown_table_codec`
/// exporteert alles hieronder door, dus elke bestaande aanroeper ziet één
/// oppervlak en er is niets te kiezen.
///
/// Zuiver Dart. Geen imports, en dat is de eigenschap die dit bestand draagt.
library;

/// Een pijp die geen celinhoud is, dus niet voorafgegaan door een backslash.
final _unescapedPipe = RegExp(r'(?<!\\)\|');

/// De scheidingsrij van een GFM-tabel (`---`, `:---`, `---:`, `:---:`).
final _separatorCell = RegExp(r'^:?-+:?$');

/// Splitst één tabelregel in cellen en draait de ontsnappingen terug.
List<String> splitMarkdownTableRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s
      .split(_unescapedPipe)
      .map((c) => unescapeMarkdownTableCell(c.trim()))
      .toList();
}

/// Draait de celontsnappingen van `encodeMarkdownTableCell` terug.
String unescapeMarkdownTableCell(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s[i] == r'\'[0] && i + 1 < s.length) {
      final n = s[i + 1];
      // `\|`, `\\` and `\<` unescape to the literal char; a `\<` keeps a
      // following `br>` as literal text rather than an author newline.
      if (n == '|' || n == r'\'[0] || n == '<') {
        out.write(n);
        i++;
        continue;
      }
    }
    // An unescaped `<br>` is an author-inserted line break.
    if (s.startsWith('<br>', i)) {
      out.write('\n');
      i += 3; // skip 'br>'; the loop's i++ steps past the '<'
      continue;
    }
    out.write(s[i]);
  }
  return out.toString();
}

/// Of [line] eruitziet als een regel van een Markdown-tabel.
bool isMarkdownTableLine(String line) {
  final t = line.trim();
  return t.startsWith('|') && t.length > 1;
}

/// Of [line] de GFM-scheidingsrij ónder een tabelkop is (`| --- | :--: |`): een
/// tabelregel waarvan élke cel `:?-+:?` is. Voor een parser die een tabel-*start*
/// moet herkennen (koprij gevolgd door deze rij) zonder de hele tabel te
/// decoderen — zie de documentmodus-weergave, `DocumentDeckBridge` en
/// `pentest_blocks`.
bool isMarkdownTableDelimiterRow(String line) {
  if (!isMarkdownTableLine(line)) return false;
  final cells = splitMarkdownTableRow(line);
  return cells.isNotEmpty &&
      cells.every((c) => _separatorCell.hasMatch(c.trim()));
}
