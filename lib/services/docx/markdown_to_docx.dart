// Markdown → WordprocessingML (OOXML .docx) body-converter.
//
// Zet een GFM-Markdown-string om in een WordprocessingML body-fragment (de
// inhoud van `<w:body>`). Headless: geen Flutter, geen IO. De aanroeper
// verpakt dit in word/document.xml met stijlen, relaties en metadata
// (zie document_docx_export.dart).
//
// Hergebruikt de `markdown`-package als AST-parser — hetzelfde patroon als
// lib/services/odt/markdown_to_odt.dart en
// lib/services/latex/markdown_to_latex.dart. Geen nieuwe dependency.
//
// WordprocessingML kent, in tegenstelling tot ODT, geen inline href bij een
// hyperlink: een externe link refereert een relatie in
// `word/_rels/document.xml.rels`. Daarom emit de converter een
// `<OCIDECKLINK href="…">…</OCIDECKLINK>`-sentinel die de export-service
// vervangt door `<w:hyperlink r:id="rIdN">` met de bijbehorende relatie.
// Afbeeldingen en mermaid-diagrammen gaan via vergelijkbare sentinels, zodat
// de converter zelf geen relaties hoeft te tellen — één bron, één telling.
//
// Elke tekst-node wordt een eigen `<w:r>` met de op dat moment geldende
// run-properties (vet, cursief, …). Geneste inline-opmaak (`**_bold
// italic_**`) accumuleert properties in één run in plaats van runs te
// nesten — WordprocessingML staat geneste runs niet toe.

import 'package:markdown/markdown.dart' as md;

import '../../utils/export_link.dart';
import '../../utils/footnotes.dart';
import '../document_footnote_setup.dart';
import '../document_timeline.dart';
import '../../utils/xml_escape.dart';

/// Het resultaat van de Markdown→WordprocessingML-conversie.
class DocxConversion {
  const DocxConversion({
    required this.body,
    required this.footnotes,
    required this.mermaidSources,
    required this.mathSources,
    required this.imageSources,
    required this.linkTargets,
  });

  /// De body-XML (inhoud van `<w:body>`), met sentinels voor afbeeldingen,
  /// links, mermaid- en wiskundeblokken die de export-service oplost.
  final String body;

  /// De voetnootdefinities, in volgorde van nummer, voor `footnotes.xml`
  /// (of `endnotes.xml`).
  final List<DocxFootnoteDef> footnotes;

  /// De bron van elk mermaid-blok, in volgorde van voorkomen — de
  /// export-service rasteriseert deze naar PNG.
  final List<String> mermaidSources;

  /// De bron van elk wiskundeblok (display-math), in volgorde van voorkomen.
  final List<String> mathSources;

  /// De `src`-waarde van elke `<img>` in volgorde van voorkomen — de
  /// export-service haalt de bytes op via `embedImage`.
  final List<String> imageSources;

  /// De externe linkdoelen in volgorde van voorkomen, voor de relaties.
  final List<String> linkTargets;
}

/// Eén voetnootdefinitie voor `footnotes.xml`/`endnotes.xml`.
class DocxFootnoteDef {
  const DocxFootnoteDef({required this.number, required this.inlineXml});

  final int number;

  /// De noot-inhoud als WordprocessingML-runs (al inline-geconverteerd).
  final String inlineXml;
}

/// Zet [markdown] (GFM) om in een WordprocessingML body-fragment plus de
/// nevenproducten die de export-service nodig heeft.
///
/// [chapterPageBreak] laat elk H1 (behalve het eerste) op een nieuwe pagina
/// beginnen via `<w:pageBreakBefore/>`.
/// [footnotePlacement] bepaalt of noten als voetnoot (`footnotes.xml`) of
/// eindnoot (`endnotes.xml`) worden gemarkeerd — de sentinel is hetzelfde;
/// de export-service kiest het bestand.
/// [tableHeaderFill] is de `RRGGBB`-vulling die op de kopcellen van een tabel
/// komt (`w:shd`), uit `ThemeProfile.tableHeaderBackgroundColor`. `null`
/// laat de cel ongevuld — voor aanroepen die geen profiel kennen.
/// [contentWidthTwips] is de breedte van de tekstkolom (paginabreedte minus
/// de marges); tabellen verdelen die breedte over hun kolommen, zodat een
/// brede tabel niet buiten het papier valt.
DocxConversion markdownToDocxBody(
  String markdown, {
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String? tableHeaderFill,
  int contentWidthTwips = defaultContentWidthTwips,
}) {
  if (markdown.trim().isEmpty) {
    return const DocxConversion(
      body: '',
      footnotes: [],
      mermaidSources: [],
      mathSources: [],
      imageSources: [],
      linkTargets: [],
    );
  }

  // Voetnoten: verwijzingen worden sentinels, definities verdwijnen uit de
  // body. De noot-inhoud gaat naar footnotes.xml/endnotes.xml.
  final notes = documentFootnotes(markdown);
  var source = stripFootnoteDefinitions(markdown);

  // Tijdlijnen beschermen vóór de parse, net als de ODT-converter.
  final timelines = _protectDocumentTimelines(
    source,
    headerFill: tableHeaderFill,
    contentWidthTwips: contentWidthTwips,
  );
  source = timelines.source;

  // Voetnootverwijzingen → sentinels vóór de parse.
  final noteSentinels = <String, Footnote>{};
  for (final note in notes) {
    final sentinel = 'OCIDECKFOOTNOTE${note.number}END';
    noteSentinels[sentinel] = note;
    source = source.replaceAll('[^${note.label}]', sentinel);
  }

  final document = md.Document(
    encodeHtml: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parse(source);
  final visitor = _DocxNodeVisitor(
    chapterPageBreak: chapterPageBreak,
    tableHeaderFill: tableHeaderFill,
    contentWidthTwips: contentWidthTwips,
  );
  for (final node in nodes) {
    node.accept(visitor);
  }

  var out = visitor.output.toString();

  // Tijdlijn-placeholders herstellen.
  for (var i = 0; i < timelines.docx.length; i++) {
    out = out.replaceAll('OCIDECKTIMELINE${i}END', timelines.docx[i]);
  }

  // Voetnoot-sentinels → `<w:footnoteReference w:id="n"/>`. De definities
  // worden apart verzameld voor footnotes.xml. Word eist id≥1 voor echte
  // noten (id 0 is de scheidingstekst-separator); het nummer van de noot
  // loopt vanaf 1, dus dat klopt al.
  final footnoteDefs = <DocxFootnoteDef>[];
  for (final entry in noteSentinels.entries) {
    final note = entry.value;
    final id = note.number;
    footnoteDefs.add(
      DocxFootnoteDef(number: id, inlineXml: _inlineDocx(note.text)),
    );
    out = out.replaceAll(
      entry.key,
      '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>'
      '<w:footnoteReference w:id="$id"/></w:r>',
    );
  }
  footnoteDefs.sort((a, b) => a.number.compareTo(b.number));

  return DocxConversion(
    body: out.trimRight(),
    footnotes: footnoteDefs,
    mermaidSources: visitor.mermaidSources,
    mathSources: visitor.mathSources,
    imageSources: visitor.imageSources,
    linkTargets: visitor.linkTargets,
  );
}

/// Bescherm tijdlijn-tabellen vóór de parse. De markdown-package rendert een
/// tijdlijn als een gewone tabel — voor docx volstaat dat, de marker blijft
/// als commentaar zichtbaar voor wie de bron kent.
({String source, List<String> docx}) _protectDocumentTimelines(
  String source, {
  String? headerFill,
  required int contentWidthTwips,
}) {
  final r = protectTimelines(
    source,
    (timeline) => _renderTimelineDocx(
      timeline,
      headerFill: headerFill,
      contentWidthTwips: contentWidthTwips,
    ),
  );
  return (source: r.source, docx: r.rendered);
}

/// De breedte van de tekstkolom op A4-staand met de marges die de
/// DOCX-export zet (20 mm links en rechts): 11906 − 2 × 1134 twips.
/// Aanroepers met een andere paginaopmaak geven hun eigen breedte mee.
const int defaultContentWidthTwips = 9638;

/// De kolombreedte voor een tabel van [colCount] kolommen binnen een
/// tekstkolom van [contentWidthTwips]: gelijk verdeeld, zodat een tabel van
/// vijf kolommen niet buiten het papier valt. Een tabel houdt zo altijd
/// dezelfde buitenmaat als de lopende tekst.
int columnWidthTwips(int colCount, int contentWidthTwips) =>
    colCount <= 0 ? contentWidthTwips : contentWidthTwips ~/ colCount;

/// `w:tbl` plus `w:tblPr` en `w:tblGrid` voor een tabel van [colCount]
/// kolommen. De breedte staat vast (`w:tblLayout fixed`) omdat Word,
/// LibreOffice en Pages `w:type="auto"` alle drie anders uitleggen; met een
/// vaste opmaak toont het papier overal dezelfde tabel.
String _tableOpenXml(int colCount, int contentWidthTwips) {
  final col = columnWidthTwips(colCount, contentWidthTwips);
  final grid = StringBuffer();
  for (var i = 0; i < colCount; i++) {
    grid.write('<w:gridCol w:w="$col"/>');
  }
  return '<w:tbl><w:tblPr><w:tblW w:w="${col * colCount}" w:type="dxa"/>'
      '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '</w:tblBorders><w:tblLayout w:type="fixed"/></w:tblPr>'
      '<w:tblGrid>$grid</w:tblGrid>';
}

String _renderTimelineDocx(
  DocumentTimeline timeline, {
  String? headerFill,
  required int contentWidthTwips,
}) {
  // De tijdlijn wordt als Word-tabel gerenderd. De `<!-- timeline -->`-marker
  // blijft in de Markdown-bron staan maar gaat hier niet mee: een
  // XML-commentaar in het document draagt niets en maakt de body alleen
  // zwaarder.
  final cols = timeline.headers.length;
  final width = columnWidthTwips(cols, contentWidthTwips);
  final buf = StringBuffer();
  buf.write(_tableOpenXml(cols, contentWidthTwips));
  // Koptekstrij.
  buf.write('<w:tr><w:trPr><w:tblHeader/></w:trPr>');
  for (final header in timeline.headers) {
    buf.write(_tableCell(header, width: width, header: true, fill: headerFill));
  }
  buf.write('</w:tr>');
  for (final event in timeline.events) {
    buf.write('<w:tr>');
    buf.write(_tableCell(event.marker, width: width));
    buf.write(_tableCell(event.event, width: width));
    buf.write(_tableCell(event.metadata ?? '', width: width));
    buf.write('</w:tr>');
  }
  buf.writeln('</w:tbl>');
  // Een lege alinea na de tabel, anders plakt de volgende tekst vast.
  buf.writeln('<w:p/>');
  return buf.toString();
}

String _tableCell(
  String text, {
  required int width,
  bool header = false,
  String? fill,
}) {
  final shd = fill == null
      ? ''
      : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>';
  final style = header ? 'TableHeading' : 'TableContents';
  return '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>$shd</w:tcPr>'
      '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r>'
      '</w:p></w:tc>';
}

/// De inline-markdown van een noot als WordprocessingML-runs — vet, cursief,
/// code en links, maar geen alinea's.
String _inlineDocx(String text) {
  final html = md.markdownToHtml(
    text,
    inlineOnly: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return _htmlInlineToDocx(html);
}

/// Vertaalt eenvoudige inline-HTML (van de markdown-package) naar
/// WordprocessingML-runs.
String _htmlInlineToDocx(String html) {
  var result = html;
  result = result.replaceAllMapped(
    RegExp(r'<strong>(.*?)</strong>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<em>(.*?)</em>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:i/></w:rPr><w:t xml:space="preserve">${xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<del>(.*?)</del>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:strike/></w:rPr><w:t xml:space="preserve">${xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<code>(.*?)</code>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:rStyle w:val="SourceText"/></w:rPr><w:t xml:space="preserve">${xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<a href="([^"]*)">(.*?)</a>', dotAll: true),
    (m) =>
        '<OCIDECKLINK href="${xmlAttr(m.group(1)!)}">'
        '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
        '<w:t xml:space="preserve">${xmlEscape(m.group(2)!)}</w:t></w:r>'
        '</OCIDECKLINK>',
  );
  result = result.replaceAll('<br>', '<w:r><w:br/></w:r>');
  result = result.replaceAll('<br/>', '<w:r><w:br/></w:r>');
  // Overgebleven kale tekst → een run.
  result = result.replaceAllMapped(RegExp(r'(?<![>])[^<]+'), (m) {
    final t = m.group(0)!;
    if (t.trim().isEmpty) return t;
    return '<w:r><w:t xml:space="preserve">${xmlEscape(t)}</w:t></w:r>';
  });
  return result;
}

class _DocxNodeVisitor implements md.NodeVisitor {
  _DocxNodeVisitor({
    this.chapterPageBreak = false,
    this.tableHeaderFill,
    this.contentWidthTwips = defaultContentWidthTwips,
  });

  final StringBuffer output = StringBuffer();
  final bool chapterPageBreak;

  /// De `RRGGBB`-vulling voor tabelkopcellen, of `null` voor geen vulling.
  final String? tableHeaderFill;

  /// De breedte van de tekstkolom, waarover tabellen hun kolommen verdelen.
  final int contentWidthTwips;

  bool _seenChapter = false;

  /// Of er op dit moment een `<w:p>` open staat. WordprocessingML kent geen
  /// alinea in een alinea: een citaat of een lijstpunt dat een `<p>` bevat
  /// moet de lopende alinea hergebruiken of sluiten, nooit er een tweede
  /// binnenin openen. Word weigert zo'n bestand ("er zijn problemen met de
  /// inhoud"); LibreOffice herstelt het door de structuur te laten vallen.
  bool _paragraphOpen = false;

  /// Lijst-diepte (geneste lijsten). 0 = geen lijst.
  int _listDepth = 0;

  /// Of de huidige lijst geordend is, per diepteniveau.
  final List<bool> _orderedStack = [];

  /// Het kolomaantal van de tabel die op dit moment open staat — de cellen
  /// delen de tekstbreedte daarover.
  int _tableColumns = 1;

  final List<String> mermaidSources = [];
  final List<String> mathSources = [];
  final List<String> imageSources = [];
  final List<String> linkTargets = [];

  /// Stack van run-property-fragmenten voor de momenteel open inline-
  /// opmaakelementen. Elke tekst-node wordt één `<w:r>` met de join hiervan.
  final List<String> _rPr = [];

  final List<_Ctx> _stack = [];

  bool get _inCodeBlock => _stack.any((c) => c == _Ctx.codeBlock);

  bool get _inTable => _stack.any((c) => c == _Ctx.table);

  /// Opent een alinea met [pPr] als alinea-eigenschappen. Staat er nog een
  /// alinea open, dan wordt die eerst gesloten — een alinea in een alinea is
  /// geen geldige WordprocessingML.
  void _openParagraph(String pPr) {
    _closeParagraph();
    output.write('<w:p>$pPr');
    _paragraphOpen = true;
  }

  void _closeParagraph() {
    if (!_paragraphOpen) return;
    // Binnen een tabel geen regelovergang: `w:tbl`, `w:tr` en `w:tc` dragen
    // alleen elementen, geen tekst. Op blokniveau houdt de regelovergang de
    // XML leesbaar voor wie hem naast een diff legt.
    output.write(_inTable ? '</w:p>' : '</w:p>\n');
    _paragraphOpen = false;
  }

  /// De alinea-eigenschappen voor een `<p>` op blokniveau. Binnen een citaat
  /// krijgt elke alinea de Quote-stijl; binnen een lijstpunt is een tweede
  /// alinea een vervolgalinea (wel de inspringing, geen nieuw opsommingsteken).
  String _blockParagraphPr() {
    for (final ctx in _stack.reversed) {
      if (ctx == _Ctx.blockquote) {
        return '<w:pPr><w:pStyle w:val="Quote"/></w:pPr>';
      }
      if (ctx == _Ctx.listItem) {
        final left = 720 + (_listDepth - 1).clamp(0, 5) * 360;
        return '<w:pPr><w:pStyle w:val="ListParagraph"/>'
            '<w:ind w:left="$left"/></w:pPr>';
      }
      if (ctx == _Ctx.tableCell) return '';
    }
    return '';
  }

  @override
  void visitText(md.Text text) {
    if (_inCodeBlock) {
      // Code-blok-tekst wordt in _visitCode afgehandeld.
      return;
    }
    // Losse tekst op blokniveau (een citaat zonder alinea, bijvoorbeeld) hoort
    // toch in een alinea: een `<w:r>` direct onder `<w:body>` is ongeldig.
    if (!_paragraphOpen) _openParagraph(_blockParagraphPr());
    // Elke tekst-node wordt een eigen run met de geldende run-properties.
    // `xml:space="preserve"` houdt voorloop- en achterloopspaties staan —
    // zonder dat plakt "vet " aan de volgende run vast.
    output.write(
      '<w:r>${_rPrXml()}<w:t xml:space="preserve">${text.text}</w:t></w:r>',
    );
  }

  String _rPrXml() {
    if (_rPr.isEmpty) return '';
    // OOXML vereist een specifieke volgorde van kind-elementen in w:rPr
    // (rStyle → b → i → strike → …). De _rPr-stack hanteert de open-volgorde
    // van de markdown-nesting, die niet altijd de schema-volgorde is —
    // bijv. `_`code`_` hoopt <w:i/> vóór <w:rStyle> op. Sorteer op schema-rang
    // bij het emitren, zonder de stack zelf te wijzigen (pop heeft de
    // oorspronkelijke volgorde nodig).
    if (_rPr.length == 1) return '<w:rPr>${_rPr.first}</w:rPr>';
    final ordered = List<String>.from(_rPr)
      ..sort((a, b) => _rPrRank(a).compareTo(_rPrRank(b)));
    return '<w:rPr>${ordered.join()}</w:rPr>';
  }

  /// Schema-rang van een w:rPr-kind-element (ECMA-376 CT_RPr volgorde).
  static int _rPrRank(String s) {
    if (s.contains('rStyle')) return 0;
    if (s.contains('<w:b/>')) return 1;
    if (s.contains('<w:i/>')) return 2;
    if (s.contains('<w:strike/>')) return 3;
    return 9;
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      // ── Koppen ──
      case 'h1':
        _openHeading(1);
        _seenChapter = true;
      case 'h2':
        _openHeading(2);
      case 'h3':
        _openHeading(3);
      case 'h4':
        _openHeading(4);
      case 'h5':
        _openHeading(5);
      case 'h6':
        _openHeading(6);

      // ── Alinea's en blokken ──
      case 'p':
        // Een tijdlijn is vóór de parse een sentinel op een eigen regel
        // geworden, waar de parser een alinea van maakt. De tabel die straks
        // in de plaats van de sentinel komt hoort naast een alinea, niet in
        // een `w:t` — Word weigert een tabel binnen een tekstelement.
        final blockSentinel = _loneBlockSentinel(element);
        if (blockSentinel != null) {
          _closeParagraph();
          output.write('$blockSentinel\n');
          return false;
        }
        // Binnen een lijstpunt heeft `li` de alinea al geopend; die wordt
        // hergebruikt in plaats van er een tweede binnenin te openen.
        if (_paragraphOpen) {
          _stack.add(_Ctx.reusedParagraph);
        } else {
          _openParagraph(_blockParagraphPr());
          _stack.add(_Ctx.paragraph);
        }
      case 'blockquote':
        // Een citaat opent zelf géén alinea: zijn kind-alinea's krijgen de
        // Quote-stijl via _blockParagraphPr.
        _closeParagraph();
        _stack.add(_Ctx.blockquote);
      case 'hr':
        _closeParagraph();
        output.write(
          '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" '
          'w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>',
        );
        return false;

      // ── Lijsten ──
      case 'ul':
        _orderedStack.add(false);
        _listDepth++;
        _stack.add(_Ctx.unorderedList);
        return true;
      case 'ol':
        _orderedStack.add(true);
        _listDepth++;
        _stack.add(_Ctx.orderedList);
        return true;
      case 'li':
        final ordered = _orderedStack.isEmpty ? false : _orderedStack.last;
        final numId = ordered ? 2 : 1;
        final ilvl = _listDepth - 1;
        _openParagraph(
          '<w:pPr><w:pStyle w:val="ListParagraph"/>'
          '<w:numPr><w:ilvl w:val="$ilvl"/><w:numId w:val="$numId"/></w:numPr>'
          '<w:ind w:left="${720 + ilvl * 360}" w:hanging="360"/></w:pPr>',
        );
        _stack.add(_Ctx.listItem);
      case 'input':
        return false;

      // ── Code ──
      case 'pre':
        _stack.add(_Ctx.codeBlock);
        return true;
      case 'code':
        return _visitCode(element);

      // ── Inline-opmaak: push run-properties ──
      case 'strong':
      case 'b':
        _rPr.add('<w:b/>');
        _stack.add(_Ctx.inline);
      case 'em':
      case 'i':
        _rPr.add('<w:i/>');
        _stack.add(_Ctx.inline);
      case 'del':
      case 's':
        _rPr.add('<w:strike/>');
        _stack.add(_Ctx.inline);

      // ── Links en afbeeldingen ──
      case 'a':
        final href = safeExportLink(element.attributes['href']);
        if (href == null) {
          _stack.add(_Ctx.passThrough);
        } else {
          output.write('<OCIDECKLINK href="${xmlAttr(href)}">');
          linkTargets.add(href);
          _rPr.add('<w:rStyle w:val="Hyperlink"/>');
          _stack.add(_Ctx.link);
        }
      case 'img':
        _visitImage(element);
        return false;

      // ── Regelonderbreking ──
      case 'br':
        output.write('<w:r><w:br/></w:r>');
        return false;

      // ── Tabellen (GFM) ──
      case 'table':
        // Een tabel staat naast een alinea, nooit erin.
        _closeParagraph();
        _stack.add(_Ctx.table);
        _tableColumns = _tableColumnCount(element);
        output.write(_tableOpenXml(_tableColumns, contentWidthTwips));
        return true;
      case 'thead':
        _stack.add(_Ctx.tableHeader);
        return true;
      case 'tbody':
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tr':
        _stack.add(_Ctx.tableRow);
        final inHeader = _stack.any((c) => c == _Ctx.tableHeader);
        output.write('<w:tr>');
        if (inHeader) output.write('<w:trPr><w:tblHeader/></w:trPr>');
        return true;
      case 'th':
        _openTableCell(element, header: true);
      case 'td':
        _openTableCell(element, header: false);

      default:
        _stack.add(_Ctx.passThrough);
    }
    return true;
  }

  void _openHeading(int level) {
    final breakBefore = chapterPageBreak && level == 1 && _seenChapter;
    final pageBreak = breakBefore ? '<w:pageBreakBefore/>' : '';
    _openParagraph(
      '<w:pPr><w:pStyle w:val="Heading$level"/>$pageBreak</w:pPr>',
    );
    _rPr.add('<w:b/>');
    _stack.add(_Ctx.heading);
  }

  void _openTableCell(md.Element element, {required bool header}) {
    _stack.add(_Ctx.tableCell);
    final shd = header && tableHeaderFill != null
        ? '<w:shd w:val="clear" w:color="auto" w:fill="$tableHeaderFill"/>'
        : '';
    final width = columnWidthTwips(_tableColumns, contentWidthTwips);
    output.write(
      '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>$shd</w:tcPr>',
    );
    // Vet en de koptekstkleur zitten in de TableHeading-stijl; hier blijft
    // alleen de uitlijning als alinea-eigenschap over.
    _openParagraph(
      '<w:pPr><w:pStyle w:val="${header ? 'TableHeading' : 'TableContents'}"/>'
      '<w:jc w:val="${_alignVal(element.attributes['align'])}"/></w:pPr>',
    );
  }

  /// De uitlijning als `ST_Jc`-waarde. `left`/`right` en niet `start`/`end`:
  /// die laatste kwamen pas in een latere editie van het formaat, terwijl de
  /// namespace van dit document de eerste noemt. `left`/`right` staat in elke
  /// editie.
  String _alignVal(String? align) => switch (align) {
    'center' => 'center',
    'right' => 'right',
    _ => 'left',
  };

  /// De tekst van een `<p>` die niets anders bevat dan een sentinel die
  /// straks een heel blok wordt. Op dit moment is dat alleen de tijdlijn;
  /// de voetnoot- en linksentinels blijven inline en horen juist wél in een
  /// alinea.
  String? _loneBlockSentinel(md.Element element) {
    final children = element.children;
    if (children == null || children.length != 1) return null;
    final only = children.first;
    if (only is! md.Text) return null;
    final text = only.text.trim();
    return _timelineSentinel.hasMatch(text) ? text : null;
  }

  static final RegExp _timelineSentinel = RegExp(r'^OCIDECKTIMELINE\d+END$');

  int _tableColumnCount(md.Element table) {
    final firstRow = table.children?.whereType<md.Element>().firstWhere(
      (e) => e.tag == 'thead' || e.tag == 'tbody',
      orElse: () => table.children!.first as md.Element,
    );
    final rows = firstRow?.children ?? [];
    if (rows.isEmpty) return 1;
    final firstRowElement = rows.first as md.Element;
    return firstRowElement.children?.length ?? 1;
  }

  bool _visitCode(md.Element element) {
    if (_inCodeBlock) {
      // Bepaal de taal: de markdown-package zet die als class="language-X"
      // op de <code> binnen een <pre>.
      final classes = element.attributes['class'] ?? '';
      final langMatch = RegExp(r'language-([\w-]+)').firstMatch(classes);
      final lang = langMatch?.group(1);

      final codeText =
          element.children?.whereType<md.Text>().fold(
            '',
            (acc, t) => acc + t.text,
          ) ??
          '';

      // Een codeblok, diagram of formule staat op blokniveau: een lijstpunt
      // dat er een bevat moet zijn alinea eerst sluiten.
      _closeParagraph();

      // Mermaid- en wiskundeblokken worden sentinels; de export-service
      // rasteriseert mermaid naar PNG en zet wiskunde om (of valt terug op
      // bron). Mermaid heet hier 'mermaid'; display-math komt binnen als
      // language-math of language-tex.
      if (lang == 'mermaid') {
        final idx = mermaidSources.length;
        mermaidSources.add(codeText);
        output.write('<OCIDECKMERMAID w:idx="$idx"/>');
        return false;
      }
      if (lang == 'math' || lang == 'tex' || lang == 'latex') {
        final idx = mathSources.length;
        mathSources.add(codeText);
        output.write('<OCIDECKMATH w:idx="$idx"/>');
        return false;
      }

      // Gewoon codeblok: elke regel een eigen PreformattedText-alinea.
      final lines = codeText.split('\n');
      for (final line in lines) {
        output.write(
          '<w:p><w:pPr><w:pStyle w:val="PreformattedText"/></w:pPr>'
          '<w:r><w:rPr><w:rStyle w:val="SourceText"/></w:rPr>'
          '<w:t xml:space="preserve">${xmlEscape(line)}</w:t></w:r></w:p>',
        );
      }
      // Geen stack-push: visitElementBefore returnt false, dus
      // visitElementAfter wordt niet aangeroepen — pre's visitElementAfter
      // moet _Ctx.codeBlock treffen, niet een placeholder.
      return false;
    } else {
      // Inline-code: push de stijl; de tekst-node emit de run.
      _rPr.add('<w:rStyle w:val="SourceText"/>');
      _stack.add(_Ctx.inlineCode);
      return true;
    }
  }

  void _visitImage(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    if (src.isEmpty) return;
    final idx = imageSources.length;
    imageSources.add(src);
    output.write('<OCIDECKIMG w:idx="$idx" w:alt="${xmlAttr(alt)}"/>');
  }

  @override
  void visitElementAfter(md.Element element) {
    final ctx = _stack.removeLast();
    switch (element.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _rPr.removeLast();
        _closeParagraph();

      case 'p':
        // Ook een hergebruikte alinea (`<p>` binnen een lijstpunt) sluit
        // hier: een tweede `<p>` in hetzelfde punt opent dan een eigen
        // vervolgalinea in plaats van tegen de eerste aan te plakken.
        _closeParagraph();

      case 'blockquote':
        _closeParagraph();

      case 'ul':
        _orderedStack.removeLast();
        _listDepth--;
      case 'ol':
        _orderedStack.removeLast();
        _listDepth--;
      case 'li':
        _closeParagraph();

      case 'pre':
        break;
      case 'code':
        if (ctx == _Ctx.inlineCode) {
          _rPr.removeLast();
        }

      case 'strong':
      case 'b':
      case 'em':
      case 'i':
      case 'del':
      case 's':
        _rPr.removeLast();

      case 'a':
        if (ctx == _Ctx.link) {
          _rPr.removeLast();
          output.write('</OCIDECKLINK>');
        }

      case 'th':
      case 'td':
        _closeParagraph();
        output.write('</w:tc>');
      case 'tr':
        output.write('</w:tr>');
      case 'thead':
        break;
      case 'tbody':
        break;
      case 'table':
        output.write('</w:tbl>\n<w:p/>\n');

      default:
        break;
    }
  }
}

enum _Ctx {
  passThrough,
  heading,
  paragraph,

  /// Een `<p>` die de alinea van zijn blok (een lijstpunt) hergebruikt in
  /// plaats van er een nieuwe binnenin te openen.
  reusedParagraph,
  blockquote,
  unorderedList,
  orderedList,
  listItem,
  codeBlock,
  inlineCode,
  inline,
  link,
  table,
  tableHeader,
  tableRow,
  tableCell,
}
