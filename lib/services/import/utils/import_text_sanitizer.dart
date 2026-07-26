/// Neutraliseert Markdown- en HTML-injectie in tekst uit een geïmporteerde
/// presentatie, aan de importgrens (#876).
///
/// Tekst uit een `.pptx`/`.odp`/`.key` is **data van een aanvaller**, geen
/// door de gebruiker geschreven Markdown. Zonder deze stap komen titels,
/// alinea's, bullets, quotes en linkteksten rauw in het `.md`, waar
/// Markdown-metatekens, slide-separators, Marp-directives, afbeeldings-/
/// linksyntax en HTML structurele betekenis krijgen — extra dia's, een
/// externe afbeelding die de zaal ophaalt, of `<script>` dat bij een
/// HTML-export draait.
///
/// De keuze (afgestemd, #876) is neutraliseren *aan de importgrens*, niet in de
/// serialisatielaag: alleen geïmporteerde tekst wordt geraakt, het `.md`-formaat
/// voor eigen decks blijft ongewijzigd. De prijs is dat een bron-metateken als
/// zichtbare ontsnapping (`\[`, `&lt;`) in de ruwe tekst blijft staan; het
/// *rendert* correct als die letterlijke tekst, en dat is precies de bedoeling —
/// het was tenslotte tekst, geen opmaak.
///
/// Het contract is toetsbaar tegen de bestaande poort: voor elke invoer moet
/// het gegenereerde deck door [MarkdownSafetyScanner] komen. De scanner
/// decodeert *numerieke* HTML-entities maar geen named entities, dus
/// `&amp;`/`&lt;`/`&gt;` zijn een veilige, inerte weergave — mits `&` als eerste
/// wordt ontsnapt, zodat een bron-`&#60;` `&amp;#60;` wordt en niet meer als
/// `<` teruggelezen kan worden.
library;

/// Een leidend blokteken maakt van een hele regel een kop, lijst, thematische
/// breuk of tabel. Omdat de tekst tot één regel is gevouwen, telt alleen de
/// eerste positie. `_`, `*` en `-` dekken ook de `___`/`***`/`---` thematische
/// breuken. `>` (blockquote) staat er niet in: dat teken is op dit punt al door
/// de HTML-escape `&gt;` geworden, wat als letterlijke `>` rendert.
final RegExp _leadingBlockMarker = RegExp(r'^([#\-+*_|=~`])');

/// Een leidende geordende-lijstmarkering (`1.` / `2)`).
final RegExp _leadingOrderedList = RegExp(r'^(\d{1,9})([.)])(\s)');

/// Maak [raw] veilig om als letterlijke tekst in een **rauw geserialiseerd**
/// veld (titel, kop, alinea, bullet, quote, vrije Markdown) te landen — een
/// context zonder eigen escaper.
///
/// De stappen, in deze volgorde:
/// 1. **Eén regel.** Regeleinden (incl. `\r`) worden spaties, randruimte weg —
///    zo kan tekst niet in een volgend blok breken en verdwijnt een kale `\r`
///    die de YAML-front-matter zou splitsen.
/// 2. **Backslash eerst.** Een bron-`\` wordt `\\`, zodat een bron-`\#` letterlijk
///    blijft en niet met een ontsnapping die wij toevoegen versmelt.
/// 3. **HTML-escape** `&`, `<`, `>` — defuset elke `<tag…`-vector die de scanner
///    kent (script, iframe, `on…=`, Marp-`<!--`), en de numerieke-entity-evasie.
/// 4. **Link/afbeelding onschadelijk.** `[` wordt `\[` (geen link/afbeelding
///    vormt zich), en de reeks `](` wordt `]\(` (breekt de scanner-detectie van
///    `](javascript:` / `](data:text/html` zonder alle haakjes in proza te raken).
/// 5. **Leidend blokteken** ontsnappen — een regel die met `#`, `-`, `|`,
///    … of `1.` begint, wordt anders een kop/lijst/breuk/tabel.
String sanitizeImportedText(String raw) {
  var s = raw.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();
  if (s.isEmpty) return s;

  s = s.replaceAll(r'\', r'\\');
  s = _escapeHtmlAndLinks(s);

  s = s.replaceFirstMapped(_leadingBlockMarker, (m) => '\\${m[1]}');
  s = s.replaceFirstMapped(
    _leadingOrderedList,
    (m) => '${m[1]}\\${m[2]}${m[3]}',
  );
  return s;
}

/// Neutraliseer [raw] voor een **inline** context die al een eigen structurele
/// escaper heeft: een tabelcel (`encodeMarkdownTableCell` doet `|`/`\`/`<br>`)
/// of een notitie (`_escapeNotes` doet `-->`). Die escaper dekt de structuur en
/// de backslash; wat hij mist is precies de HTML-/scriptinjectie en de
/// link-/afbeeldingssyntax — en dát doet deze variant.
///
/// Bewust *geen* backslash-verdubbeling (de cel-escaper doet dat al; verdubbelen
/// zou dubbel escapen), *geen* regelinvouwen (een notitie is meerregelig, en een
/// cel breekt regels zelf naar `<br>`), en *geen* leidend-blokteken-ontsnapping
/// (een cel of notitie staat niet aan een regelbegin, dus een `-5` blijft `-5`
/// in plaats van `\-5`). Componeert zo schoon met de bestaande escaper.
String sanitizeImportedInline(String raw) => _escapeHtmlAndLinks(raw);

/// De gedeelde kern van beide varianten: HTML-metatekens onschadelijk en de
/// link-/afbeeldingssyntax gebroken. `&` eerst, zodat een bron-`&#60;` `&amp;#60;`
/// wordt en de scanner hem niet meer als `<` terugleest.
String _escapeHtmlAndLinks(String s) {
  s = s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return s.replaceAll('[', r'\[').replaceAll('](', r']\(');
}
