/// Gedeelde, laag-neutrale Markdown-blokprimitieven voor de documentmodus:
/// GFM-pijptabellen en de ` ```chart `-fence.
///
/// Ze wonen hier — in `utils/`, dat zowel widgets als services mogen importeren —
/// zodat de weergave (`DocumentMarkdownView`), het editor-scherm, de deck-bridge
/// (`DocumentDeckBridge`), de HTML-export (`MarpHtmlService`) en de grafiek-
/// hydratie naar één bron wijzen. Voorheen droeg elk een byte-getrouwe kopie,
/// bewust herhaald omdat de laagpoort een service `lib/widgets/` niet laat
/// importeren — een util lost dat op zonder die grens te schenden. Wat de
/// weergave telt/toont en wat de bridge deconstrueert moet gelijk blijven, dus
/// één definitie voorkomt dat de kopieën uit elkaar lopen.
///
/// **Bewust apart van `services/markdown_table_codec.dart`.** Die codec draagt
/// de rijkere, app-interne conventie (`<br>` → een echte regelovergang, `\\` →
/// backslash) voor de rapportagedia's, de import en het klembord. De
/// documentmodus bewerkt echter *platte gebruikers-Markdown* met een
/// byte-getrouwe round-trip als rode lijn: een `<br>` die een auteur letterlijk
/// typt (geldige inline-HTML in GFM) mag níét stil een regelovergang worden.
/// Daarom houdt de documentmodus de eenvoudige, alleen-`\|`-ontsnapping hier —
/// een ander contract, geen toevallige kopie.
library;

/// De fence van één ` ```chart `-blok; de kale spec-tekst staat in groep 1.
/// Dezelfde vorm die de weergave rendert, de editor vervangt, de export omzet en
/// de hydratie invult — zodat ze naar exact dezelfde blokken wijzen.
final RegExp chartFencePattern = RegExp(
  r'```chart[ \t]*\n([\s\S]*?)\n```',
  multiLine: true,
);

/// Een regel die als GFM-pijptabelrij leest: na trimmen bevat hij een `|` en
/// begint hij ermee.
bool looksLikeTableRow(String line) {
  final t = line.trim();
  return t.contains('|') && t.startsWith('|');
}

/// De scheidingsrij onder een tabelkop, bijv. `| --- | :--: |`.
bool isTableDelimiter(String line) {
  final t = line.trim();
  if (!t.contains('-') || !t.contains('|')) return false;
  return RegExp(r'^\|?[\s:|-]+\|?$').hasMatch(t);
}

/// Splits een tabelrij op onontsnapte `|`, ontdaan van de buitenste pipes, elke
/// cel getrimd. Een ontsnapte `\|` blijft als `\|` in de cel staan (zie
/// [gfmTableCells] voor de ontsnapping-vrije vorm).
List<String> splitTableRow(String row) {
  var t = row.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == r'\' && i + 1 < t.length) {
      buf.write(c);
      buf.write(t[i + 1]);
      i++;
      continue;
    }
    if (c == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  cells.add(buf.toString().trim());
  return cells;
}

/// De cellen van een GFM-tabelblok (koprij + body, zónder scheidingsrij),
/// ontdaan van pipe-ontsnapping (`\|` → `|`) — de vorm die de editor en de
/// bridge verwachten.
List<List<String>> gfmTableCells(List<String> rawRows) => rawRows
    .map((r) => splitTableRow(r).map((c) => c.replaceAll(r'\|', '|')).toList())
    .toList();

/// Serialiseer een celraster (eerste rij = koppen) naar een GFM-pijptabel: een
/// koprij, een scheidingsrij en de body. Cellen met een `|` worden ontsnapt naar
/// `\|` zodat ze de kolomgrens niet breken; ragged rijen worden met lege cellen
/// aangevuld tot de breedste. Uitlijning wordt niet bewaard.
String rowsToGfmTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String cell(List<String> r, int c) =>
      (c < r.length ? r[c] : '').replaceAll('|', r'\|');
  String line(List<String> r) =>
      '| ${List.generate(cols, (c) => cell(r, c)).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(cols, '---').join(' | ')} |',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}
