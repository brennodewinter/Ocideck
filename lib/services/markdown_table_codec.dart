/// De codering van een Markdown-tabel zoals OciDeck hem schrijft en leest.
///
/// Los van `MarkdownService` omdat de HTML-export de tabellen óók moet kunnen
/// lezen: de zes rapportagetypes (`scorecard`, `assets`, `discoveries`,
/// `checklist`, `scope-matrix`, `findings-summary`) bewaren hun inhoud als een
/// gewone tabel en krijgen in de export een eigen weergave. Zonder deze module
/// zou de export zijn eigen tabelparser naast die van de parser leggen, en dan
/// gaat er precies één ding mis: de ontsnappingen. Een cel met een `|` of een
/// regeleinde erin las er dan anders uit dan hij bewaard was.
///
/// De ontsnappingen zijn: `\|` voor een letterlijke pijp, `\\` voor een
/// backslash, en `<br>` voor een regeleinde binnen een cel — met `\<br>` voor
/// een auteur die de tekens `<br>` letterlijk bedoelt.
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

/// Draait de celontsnappingen van [encodeMarkdownTableCell] terug.
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

/// Codeert één celwaarde voor een Markdown-tabel.
String encodeMarkdownTableCell(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll('|', r'\|')
    // Escape an author-typed literal "<br>" before encoding real newlines as
    // "<br>", so the two are distinguishable on parse (otherwise a literal
    // "<br>" silently became a line break every load).
    .replaceAll('<br>', r'\<br>')
    .replaceAll('\n', '<br>');

/// Leest de rijen van een tabel uit [tableLines] (de regels van de tabel, zonder
/// omringende tekst). De GFM-scheidingsrij direct ná de kop valt weg.
///
/// Alleen die ene regel telt als scheiding. Verderop is een streepje gewoon
/// inhoud — in een bevindingen- of scopetabel de gebruikelijke invulling voor
/// "niet van toepassing" — en zo'n rij werd anders in zijn geheel weggegooid,
/// inclusief de andere kolommen.
List<List<String>> decodeMarkdownTableRows(List<String> tableLines) {
  final rows = <List<String>>[];
  for (final line in tableLines) {
    final cells = splitMarkdownTableRow(line);
    if (rows.length == 1 &&
        cells.isNotEmpty &&
        cells.every((c) => _separatorCell.hasMatch(c.trim()))) {
      continue;
    }
    rows.add(cells);
  }
  return rows;
}

/// Of [line] eruitziet als een regel van een Markdown-tabel.
bool isMarkdownTableLine(String line) {
  final t = line.trim();
  return t.startsWith('|') && t.length > 1;
}
