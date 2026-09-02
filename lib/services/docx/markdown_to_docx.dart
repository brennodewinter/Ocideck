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
import '../markdown_table_lines.dart';

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
DocxConversion markdownToDocxBody(
  String markdown, {
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
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
  final timelines = _protectDocumentTimelines(source);
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
  final visitor = _DocxNodeVisitor(chapterPageBreak: chapterPageBreak);
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
({String source, List<String> docx}) _protectDocumentTimelines(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final output = <String>[];
  final rendered = <String>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].trim() != documentTimelineMarker ||
        index + 2 >= lines.length ||
        !isMarkdownTableLine(lines[index + 1]) ||
        !isMarkdownTableDelimiterRow(lines[index + 2])) {
      output.add(lines[index++]);
      continue;
    }
    var end = index + 3;
    while (end < lines.length && isMarkdownTableLine(lines[end])) {
      end++;
    }
    final marked = lines.sublist(index, end).join('\n');
    final timeline = analyzeMarkedTimeline(marked).timeline;
    if (timeline == null) {
      output.add(lines[index++]);
      continue;
    }
    // De tijdlijn wordt als Word-tabel gerenderd; de marker blijft als
    // commentaar erboven staan.
    final buf = StringBuffer('<!-- timeline -->\n');
    buf.writeln('<w:tbl>');
    buf.writeln(
      '<w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '</w:tblBorders></w:tblPr>',
    );
    buf.writeln('<w:tblGrid>');
    for (final _ in timeline.headers) {
      buf.writeln('<w:gridCol w:w="2880"/>');
    }
    buf.writeln('</w:tblGrid>');
    // Koptekstrij.
    buf.writeln('<w:tr><w:trPr><w:tblHeader/></w:trPr>');
    for (final header in timeline.headers) {
      buf.write(_tableCell(header, bold: true));
    }
    buf.writeln('</w:tr>');
    for (final event in timeline.events) {
      buf.writeln('<w:tr>');
      buf.write(_tableCell(event.marker));
      buf.write(_tableCell(event.event));
      buf.write(_tableCell(event.metadata ?? ''));
      buf.writeln('</w:tr>');
    }
    buf.writeln('</w:tbl>');
    // Een lege alinea na de tabel, anders plakt de volgende tekst vast.
    buf.writeln('<w:p/>');
    output.add('OCIDECKTIMELINE${rendered.length}END');
    rendered.add(buf.toString());
    index = end;
  }
  return (source: output.join('\n'), docx: rendered);
}

String _tableCell(String text, {bool bold = false}) {
  final rPr = bold ? '<w:rPr><w:b/></w:rPr>' : '';
  return '<w:tc><w:tcPr><w:tcW w:w="2880" w:type="dxa"/></w:tcPr>'
      '<w:p><w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r>'
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
        '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<em>(.*?)</em>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:i/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<del>(.*?)</del>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:strike/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<code>(.*?)</code>', dotAll: true),
    (m) =>
        '<w:r><w:rPr><w:rStyle w:val="SourceText"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(m.group(1)!)}</w:t></w:r>',
  );
  result = result.replaceAllMapped(
    RegExp(r'<a href="([^"]*)">(.*?)</a>', dotAll: true),
    (m) =>
        '<OCIDECKLINK href="${_xmlAttr(m.group(1)!)}">'
        '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEscape(m.group(2)!)}</w:t></w:r>'
        '</OCIDECKLINK>',
  );
  result = result.replaceAll('<br>', '<w:r><w:br/></w:r>');
  result = result.replaceAll('<br/>', '<w:r><w:br/></w:r>');
  // Overgebleven kale tekst → een run.
  result = result.replaceAllMapped(RegExp(r'(?<![>])[^<]+'), (m) {
    final t = m.group(0)!;
    if (t.trim().isEmpty) return t;
    return '<w:r><w:t xml:space="preserve">${_xmlEscape(t)}</w:t></w:r>';
  });
  return result;
}

class _DocxNodeVisitor implements md.NodeVisitor {
  _DocxNodeVisitor({this.chapterPageBreak = false});

  final StringBuffer output = StringBuffer();
  final bool chapterPageBreak;

  bool _seenChapter = false;

  /// Lijst-diepte (geneste lijsten). 0 = geen lijst.
  int _listDepth = 0;

  /// Of de huidige lijst geordend is, per diepteniveau.
  final List<bool> _orderedStack = [];

  final List<String> mermaidSources = [];
  final List<String> mathSources = [];
  final List<String> imageSources = [];
  final List<String> linkTargets = [];

  /// Stack van run-property-fragmenten voor de momenteel open inline-
  /// opmaakelementen. Elke tekst-node wordt één `<w:r>` met de join hiervan.
  final List<String> _rPr = [];

  final List<_Ctx> _stack = [];

  bool get _inCodeBlock => _stack.any((c) => c == _Ctx.codeBlock);

  @override
  void visitText(md.Text text) {
    if (_inCodeBlock) {
      // Code-blok-tekst wordt in _visitCode afgehandeld.
      return;
    }
    // Elke tekst-node wordt een eigen run met de geldende run-properties.
    // `xml:space="preserve"` houdt voorloop- en achterloopspaties staan —
    // zonder dat plakt "vet " aan de volgende run vast.
    output.write(
      '<w:r>${_rPrXml()}<w:t xml:space="preserve">${text.text}</w:t></w:r>',
    );
  }

  String _rPrXml() => _rPr.isEmpty ? '' : '<w:rPr>${_rPr.join()}</w:rPr>';

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
        output.write('<w:p>');
        _stack.add(_Ctx.paragraph);
      case 'blockquote':
        output.write('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>');
        _stack.add(_Ctx.blockquote);
      case 'hr':
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
        output.write(
          '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/>'
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
          output.write('<OCIDECKLINK href="${_xmlAttr(href)}">');
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
        _stack.add(_Ctx.table);
        final colCount = _tableColumnCount(element);
        output.write(
          '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
          '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
          '</w:tblBorders></w:tblPr><w:tblGrid>',
        );
        for (var i = 0; i < colCount; i++) {
          output.write('<w:gridCol w:w="2880"/>');
        }
        output.write('</w:tblGrid>');
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
        _stack.add(_Ctx.tableCell);
        output.write(
          '<w:tc><w:tcPr><w:tcW w:w="2880" w:type="dxa"/></w:tcPr>'
          '<w:p><w:pPr><w:jc w:val="${_alignVal(element.attributes['align'])}"/></w:pPr>',
        );
        _rPr.add('<w:b/>');
      case 'td':
        _stack.add(_Ctx.tableCell);
        output.write(
          '<w:tc><w:tcPr><w:tcW w:w="2880" w:type="dxa"/></w:tcPr>'
          '<w:p><w:pPr><w:jc w:val="${_alignVal(element.attributes['align'])}"/></w:pPr>',
        );

      default:
        _stack.add(_Ctx.passThrough);
    }
    return true;
  }

  void _openHeading(int level) {
    final breakBefore = chapterPageBreak && level == 1 && _seenChapter;
    output.write('<w:p><w:pPr><w:pStyle w:val="Heading$level"/>');
    if (breakBefore) output.write('<w:pageBreakBefore/>');
    output.write('</w:pPr>');
    _rPr.add('<w:b/>');
    _stack.add(_Ctx.heading);
  }

  String _alignVal(String? align) => switch (align) {
    'center' => 'center',
    'right' => 'end',
    _ => 'start',
  };

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

      // Mermaid- en wiskundeblokken worden sentinels; de export-service
      // rasteriseert mermaid naar PNG en zet wiskunde om (of valt terug op
      // bron). Mermaid heet hier 'mermaid'; display-math komt binnen als
      // language-math of language-tex.
      if (lang == 'mermaid') {
        final idx = mermaidSources.length;
        mermaidSources.add(codeText);
        output.write('<OCIDECKMERMAID w:idx="$idx"/>');
        _stack.add(_Ctx.codeBlockBody);
        return false;
      }
      if (lang == 'math' || lang == 'tex' || lang == 'latex') {
        final idx = mathSources.length;
        mathSources.add(codeText);
        output.write('<OCIDECKMATH w:idx="$idx"/>');
        _stack.add(_Ctx.codeBlockBody);
        return false;
      }

      // Gewoon codeblok: elke regel een eigen PreformattedText-alinea.
      final lines = codeText.split('\n');
      for (final line in lines) {
        output.write(
          '<w:p><w:pPr><w:pStyle w:val="PreformattedText"/></w:pPr>'
          '<w:r><w:rPr><w:rStyle w:val="SourceText"/></w:rPr>'
          '<w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>',
        );
      }
      _stack.add(_Ctx.codeBlockBody);
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
    output.write('<OCIDECKIMG w:idx="$idx" w:alt="${_xmlAttr(alt)}"/>');
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
        output.write('</w:p>\n');

      case 'p':
        if (ctx == _Ctx.paragraph) output.write('</w:p>\n');

      case 'blockquote':
        output.write('</w:p>\n');

      case 'ul':
        _orderedStack.removeLast();
        _listDepth--;
      case 'ol':
        _orderedStack.removeLast();
        _listDepth--;
      case 'li':
        output.write('</w:p>\n');

      case 'pre':
        break;
      case 'code':
        if (ctx == _Ctx.inlineCode) {
          _rPr.removeLast();
        }
      // codeBlockBody: niets te sluiten.

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
        _rPr.removeLast();
        output.write('</w:p></w:tc>\n');
      case 'td':
        output.write('</w:p></w:tc>\n');
      case 'tr':
        output.write('</w:tr>\n');
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
  blockquote,
  unorderedList,
  orderedList,
  listItem,
  codeBlock,
  codeBlockBody,
  inlineCode,
  inline,
  link,
  table,
  tableHeader,
  tableRow,
  tableCell,
}

/// XML-escape voor tekstinhoud: & < >.
String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// XML-escape voor attribuutwaarden: & < > " '.
String _xmlAttr(String s) =>
    _xmlEscape(s).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
