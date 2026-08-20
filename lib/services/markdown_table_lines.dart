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

/// Of [header] met [delimiter] eronder een tabel opent die als **één blok** door
/// de rijke-tekstlaag reist — het `x-embed-table`-blok van `EmbeddableTableSyntax`.
///
/// Dit is een *toelatingsregel*, geen smaakoordeel, en daarom bewust strenger
/// dan GFM. Wie strenger is dan de embed, laat hooguit een tabel langs de
/// scanners lopen die tóch heel was gebleven — hinderlijk, meer niet. Wie ruimer
/// is, verklaart een tabel veilig die de omzetting juist stukmaakt, en dat is
/// stille corruptie. Vandaar de drie eisen:
///
/// * beide regels dragen buitenpijpen (`isMarkdownTableLine`), want zonder die
///   herkenning weet deze zuivere regelpas niet waar de cellen liggen;
/// * hooguit drie spaties inspringing — vanaf vier is het een codeblok en leest
///   de Markdown-parser er geen tabel meer in;
/// * kop en scheidingsrij tellen **evenveel kolommen**, geteld zoals de embed
///   ze telt. Dat is de eis waar `EmbeddableTableSyntax.parse` op `null` valt,
///   en dan valt de tabel als losse tekst uiteen.
///
/// Het kolomtellen splitst daarom op élke pijp, óók een ontsnapte: zo telt de
/// embed, en een kopcel met een `\|` erin brengt hem net zo goed uit de pas.
/// [splitMarkdownTableRow] doet het andersom (die leest cellen, geen kolommen)
/// en is hier dus juist niet de goede meetlat.
bool opensAtomicMarkdownTable(String header, String? delimiter) {
  if (delimiter == null) return false;
  if (_indentWidth(header) > 3 || _indentWidth(delimiter) > 3) return false;
  if (!isMarkdownTableLine(header)) return false;
  if (!isMarkdownTableDelimiterRow(delimiter)) return false;
  return _embedColumnCount(header) == _embedColumnCount(delimiter);
}

int _indentWidth(String line) {
  var i = 0;
  while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
    i++;
  }
  return i;
}

/// Het kolomaantal van [line] zoals `EmbeddableTableSyntax` het telt: tussen de
/// openende en de sluitende pijp, gesplitst op elke pijp.
int _embedColumnCount(String line) {
  var start = _indentWidth(line);
  if (start < line.length && line[start] == '|') {
    start++;
  }
  var end = line.length;
  while (end > start && (line[end - 1] == ' ' || line[end - 1] == '\t')) {
    end--;
  }
  if (end > start && line[end - 1] == '|') end--;
  return line.substring(start, end).split('|').length;
}
