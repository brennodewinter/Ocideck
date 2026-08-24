// Markdown → OpenDocument Text (ODT) body-converter.
//
// Zet een GFM-Markdown-string om in een ODT body-fragment (de inhoud van
// `<office:text>`). Headless: geen Flutter, geen IO. De aanroeper verpakt dit
// in content.xml met stijlen en metadata (zie document_odt_export.dart).
//
// Hergebruikt de `markdown`-package als AST-parser — hetzelfde patroon als
// lib/services/epub/markdown_to_xhtml.dart en
// lib/services/latex/markdown_to_latex.dart. Geen nieuwe dependency.
//
// ODT gebruikt native voetnoten (`<text:note>`), in tegenstelling tot ePub
// waar de noten als lijst achterin staan. Dat past bij het doel van ODT: een
// bewerkbaar document waarin de ontvanger de noten kan aanpassen.

import 'package:markdown/markdown.dart' as md;

import '../../utils/export_link.dart';
import '../../utils/footnotes.dart';
import '../document_footnote_setup.dart';
import '../document_timeline.dart';
import '../markdown_table_lines.dart';

/// Zet [markdown] (GFM) om in een ODT body-fragment.
///
/// De uitvoer is platte OpenDocument XML zonder `<office:document-content>`-
/// omhulling. Bedoeld om in content.xml ingebed te worden door
/// [buildDocumentExportOdt].
///
/// [chapterPageBreak] voegt een `fo:break-before="page"` toe aan elke H1
/// behalve de eerste — voor hoofdstukken die op een nieuwe pagina beginnen.
/// [footnotesTitle] is de titel boven de noten (niet gebruikt bij ODT-native
/// voetnoten, wel bij eindnoten).
/// [footnotePlacement] bepaalt of noten als `footnote` (onderaan de pagina)
/// of `endnote` (achterin) worden gemarkeerd.
String markdownToOdtBody(
  String markdown, {
  bool chapterPageBreak = false,
  String footnotesTitle = 'Noten',
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
}) {
  if (markdown.trim().isEmpty) return '';

  // Voetnoten: ODT-native noten. De verwijzing wordt een <text:note>, de
  // definities verdwijnen uit de body — ODT rendert de noot-inhoud zelf.
  // De markdown-package kent geen tags met een colon in de naam (zoals
  // <text:note>), dus vervang de verwijzing door een sentinel vóór de parse
  // en door de echte ODT-XML ná de parse — hetzelfde patroon als de
  // tijdlijn- en TOC-sentinels.
  final notes = documentFootnotes(markdown);
  var source = stripFootnoteDefinitions(markdown);

  // Tijdlijnen: bescherm ze vóór de parse, net als de ePub- en LaTeX-converter.
  final timelines = _protectDocumentTimelines(source);
  source = timelines.source;

  // Vervang voetnootverwijzingen door sentinels vóór de parse.
  final noteSentinels = <String, Footnote>{};
  for (final note in notes) {
    final sentinel = 'OCIDECKFOOTNOTE${note.number}END';
    noteSentinels[sentinel] = note;
    source = source.replaceAll('[^${note.label}]', sentinel);
  }

  // Inhoudsopgave: `<!-- toc -->` → een placeholder die na de conversie een
  // ODT-inhoudsopgave wordt. De markdown-package stript commentaar, dus
  // vervang vóór de parse.
  const tocSentinel = 'OCIDECKTABLEOFCONTENTSMARKER';
  final withToc = source.replaceAll(
    RegExp(r'^<!-- toc -->\s*$', multiLine: true),
    tocSentinel,
  );

  final document = md.Document(
    encodeHtml: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parse(withToc);
  final visitor = _OdtNodeVisitor(chapterPageBreak: chapterPageBreak);
  for (final node in nodes) {
    node.accept(visitor);
  }

  var out = visitor.output.toString().replaceAll(
    tocSentinel,
    '<text:table-of-content text:name="Inhoudsopgave" text:protected="true">'
    '<text:index-body>'
    '<text:index-title text:style-name="Sect1_Heading">'
    '<text:p text:style-name="Heading_20_1">${_xmlEscape(footnotesTitle)}</text:p>'
    '</text:index-title>'
    '</text:index-body>'
    '</text:table-of-content>',
  );

  // Tijdlijn-placeholders herstellen.
  for (var i = 0; i < timelines.odt.length; i++) {
    out = out.replaceAll('OCIDECKTIMELINE${i}END', timelines.odt[i]);
  }

  // Voetnoot-sentinels vervangen door ODT-native <text:note>-elementen.
  final noteClass = footnotePlacement == FootnotePlacement.document
      ? 'endnote'
      : 'footnote';
  for (final entry in noteSentinels.entries) {
    final note = entry.value;
    out = out.replaceAll(
      entry.key,
      '<text:note text:note-class="$noteClass" text:id="fn${note.number}">'
      '<text:note-citation>${note.number}</text:note-citation>'
      '<text:note-body>'
      '<text:p>${_inlineOdt(note.text)}</text:p>'
      '</text:note-body>'
      '</text:note>',
    );
  }

  return out.trimRight();
}

/// De inline-markdown van een noot als ODT-fragment — vet, cursief, code en
/// links, maar geen alinea's.
String _inlineOdt(String text) {
  // Hergebruik de markdown-package voor inline parsing, maar vertaal de
  // HTML-output naar ODT. Voor eenvoudige noot-tekst volstaat dit.
  final html = md.markdownToHtml(
    text,
    inlineOnly: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return _htmlInlineToOdt(html);
}

/// Vertaalt eenvoudige inline-HTML (van de markdown-package) naar ODT-spans.
String _htmlInlineToOdt(String html) {
  var result = html;
  result = result.replaceAll(
    '<strong>',
    '<text:span text:style-name="Strong">',
  );
  result = result.replaceAll('</strong>', '</text:span>');
  result = result.replaceAll('<em>', '<text:span text:style-name="Emphasis">');
  result = result.replaceAll('</em>', '</text:span>');
  result = result.replaceAll('<del>', '<text:span text:style-name="Strike">');
  result = result.replaceAll('</del>', '</text:span>');
  result = result.replaceAll(
    '<code>',
    '<text:span text:style-name="Source_Text">',
  );
  result = result.replaceAll('</code>', '</text:span>');
  result = result.replaceAllMapped(
    RegExp(r'<a href="([^"]*)">'),
    (m) => '<text:a xlink:href="${_xmlAttr(m.group(1)!)}" xlink:type="simple">',
  );
  result = result.replaceAll('</a>', '</text:a>');
  result = result.replaceAll('<br>', '<text:line-break/>');
  result = result.replaceAll('<br/>', '<text:line-break/>');
  // Overgebleven HTML-tags strippen.
  result = result.replaceAll(RegExp(r'</?[^>]+>'), '');
  return _xmlEscape(result);
}

/// Bescherm tijdlijn-tabellen vóór de parse. De markdown-package rendert een
/// tijdlijn als een gewone tabel — voor ODT volstaat dat, de marker blijft als
/// commentaar zichtbaar voor wie de bron kent.
({String source, List<String> odt}) _protectDocumentTimelines(String source) {
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
    // De tijdlijn wordt als ODT-tabel gerenderd; de marker blijft als
    // commentaar erboven staan.
    final buf = StringBuffer('<!-- timeline -->\n');
    buf.writeln('<table:table table:name="Tijdlijn">');
    buf.writeln(
      '<table:table-column table:number-columns-repeated="${timeline.headers.length}"/>',
    );
    buf.writeln('<table:table-header-rows>');
    buf.writeln('<table:table-row>');
    for (final header in timeline.headers) {
      buf.write(
        '<table:table-cell office:value-type="string">'
        '<text:p text:style-name="Table_20_Heading">${_xmlEscape(header)}</text:p>'
        '</table:table-cell>',
      );
    }
    buf.writeln('</table:table-row>');
    buf.writeln('</table:table-header-rows>');
    for (final event in timeline.events) {
      buf.writeln('<table:table-row>');
      buf.write(
        '<table:table-cell office:value-type="string">'
        '<text:p>${_inlineOdt(event.marker)}</text:p>'
        '</table:table-cell>',
      );
      buf.write(
        '<table:table-cell office:value-type="string">'
        '<text:p>${_inlineOdt(event.event)}</text:p>'
        '</table:table-cell>',
      );
      buf.write(
        '<table:table-cell office:value-type="string">'
        '<text:p>${_inlineOdt(event.metadata ?? '')}</text:p>'
        '</table:table-cell>',
      );
      buf.writeln('</table:table-row>');
    }
    buf.writeln('</table:table>');
    output.add('OCIDECKTIMELINE${rendered.length}END');
    rendered.add(buf.toString());
    index = end;
  }
  return (source: output.join('\n'), odt: rendered);
}

class _OdtNodeVisitor implements md.NodeVisitor {
  _OdtNodeVisitor({this.chapterPageBreak = false});

  final StringBuffer output = StringBuffer();

  /// Of elk hoofdstuk (H1) op een nieuwe pagina begint (instelling).
  final bool chapterPageBreak;

  bool _seenChapter = false;

  /// Stack van context-vlaggen per open element.
  final List<_Ctx> _stack = [];

  bool get _inCodeBlock => _stack.any((c) => c == _Ctx.codeBlock);

  StringBuffer get _buf => output;

  @override
  void visitText(md.Text text) {
    // De markdown-package met `encodeHtml: true` escaped al & < >. In ODT
    // moeten we ook " escapen in attribuutwaarden, maar tekstinhoud hoeft
    // alleen & < > ge-escape'd te worden — wat de parser al doet.
    _buf.write(text.text);
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      // ── Koppen ──
      case 'h1':
        _writeHeading(1);
        _seenChapter = true;
        _stack.add(_Ctx.heading);
      case 'h2':
        _writeHeading(2);
        _stack.add(_Ctx.heading);
      case 'h3':
        _writeHeading(3);
        _stack.add(_Ctx.heading);
      case 'h4':
        _writeHeading(4);
        _stack.add(_Ctx.heading);
      case 'h5':
        _writeHeading(5);
        _stack.add(_Ctx.heading);
      case 'h6':
        _writeHeading(6);
        _stack.add(_Ctx.heading);

      // ── Alinea's en blokken ──
      case 'p':
        output.write('<text:p>');
        _stack.add(_Ctx.paragraph);
      case 'blockquote':
        output.write('<text:p text:style-name="Quote">');
        _stack.add(_Ctx.blockquote);
      case 'hr':
        output.write('<text:p text:style-name="Horizontal_Line"/>');
        return false;

      // ── Lijsten ──
      case 'ul':
        output.write('<text:list>');
        _stack.add(_Ctx.unorderedList);
      case 'ol':
        output.write('<text:list text:style-name="Ordered_List">');
        _stack.add(_Ctx.orderedList);
      case 'li':
        output.write('<text:list-item><text:p>');
        _stack.add(_Ctx.listItem);
      case 'input':
        return false;

      // ── Code ──
      case 'pre':
        _stack.add(_Ctx.codeBlock);
        return true;
      case 'code':
        return _visitCode(element);

      // ── Inline-opmaak ──
      case 'strong':
      case 'b':
        _buf.write('<text:span text:style-name="Strong">');
        _stack.add(_Ctx.inline);
      case 'em':
      case 'i':
        _buf.write('<text:span text:style-name="Emphasis">');
        _stack.add(_Ctx.inline);
      case 'del':
      case 's':
        _buf.write('<text:span text:style-name="Strike">');
        _stack.add(_Ctx.inline);

      // ── Links en afbeeldingen ──
      case 'a':
        final href = safeExportLink(element.attributes['href']);
        if (href == null) {
          _stack.add(_Ctx.passThrough);
        } else {
          _buf.write(
            '<text:a xlink:href="${_xmlAttr(href)}" xlink:type="simple">',
          );
          _stack.add(_Ctx.link);
        }
      case 'img':
        _visitImage(element);
        return false;

      // ── Regelonderbreking ──
      case 'br':
        _buf.write('<text:line-break/>');
        return false;

      // ── Tabellen (GFM) ──
      case 'table':
        _stack.add(_Ctx.table);
        output.write('<table:table>');
        // Kolombreedtes: gelijkmatig verdeeld.
        final colCount = _tableColumnCount(element);
        output.write(
          '<table:table-column table:number-columns-repeated="$colCount"/>',
        );
        return true;
      case 'thead':
        output.write('<table:table-header-rows>');
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tbody':
        output.write('<table:table-rows>');
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tr':
        _stack.add(_Ctx.tableRow);
        output.write('<table:table-row>');
        return true;
      case 'th':
        _stack.add(_Ctx.tableCell);
        _buf.write(
          '<table:table-cell office:value-type="string">'
          '<text:p text:style-name="Table_20_Heading">',
        );
        return true;
      case 'td':
        _stack.add(_Ctx.tableCell);
        final align = element.attributes['align'];
        final styleName = align != null
            ? _alignStyleName(align)
            : 'Table_20_Contents';
        _buf.write(
          '<table:table-cell office:value-type="string">'
          '<text:p text:style-name="$styleName">',
        );
        return true;

      default:
        _stack.add(_Ctx.passThrough);
    }
    return true;
  }

  void _writeHeading(int level) {
    if (chapterPageBreak && level == 1 && _seenChapter) {
      output.write(
        '<text:h text:outline-level="$level" text:style-name="Heading_20_$level" '
        'text:restart-numbering="true">',
      );
    } else {
      output.write(
        '<text:h text:outline-level="$level" text:style-name="Heading_20_$level">',
      );
    }
  }

  int _tableColumnCount(md.Element table) {
    // Tel de cellen in de eerste rij.
    final firstRow = table.children?.whereType<md.Element>().firstWhere(
      (e) => e.tag == 'thead' || e.tag == 'tbody',
      orElse: () => table.children!.first as md.Element,
    );
    final rows = firstRow?.children ?? [];
    if (rows.isEmpty) return 1;
    final firstRowElement = rows.first as md.Element;
    return firstRowElement.children?.length ?? 1;
  }

  String _alignStyleName(String align) => switch (align) {
    'center' => 'Table_20_Center',
    'right' => 'Table_20_Right',
    _ => 'Table_20_Contents',
  };

  bool _visitCode(md.Element element) {
    if (_inCodeBlock) {
      // Code-blok: elke regel wordt een eigen <text:p> met Preformatted_Text.
      // De markdown-package levert de code-inhoud als een Text-child.
      final codeText =
          element.children?.whereType<md.Text>().fold(
            '',
            (acc, t) => acc + t.text,
          ) ??
          '';
      final lines = codeText.split('\n');
      for (final line in lines) {
        output.write(
          '<text:p text:style-name="Preformatted_Text">${_xmlEscape(line)}</text:p>',
        );
      }
      _stack.add(_Ctx.codeBlockBody);
      return false;
    } else {
      _buf.write('<text:span text:style-name="Source_Text">');
      _stack.add(_Ctx.inlineCode);
      return true;
    }
  }

  void _visitImage(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    // Afbeeldingen worden door de ODT-export herwerkt: data-URI's worden
    // naar aparte bestanden geschreven en het xlink:href-attribuut wordt
    // gerebaseerd. Hier schrijven we het originele src; de ODT-builder
    // vervangt het later.
    _buf.write(
      '<draw:frame draw:style-name="Graphics" text:anchor-type="paragraph" '
      'svg:width="15cm" svg:height="auto" draw:z-index="0">'
      '<draw:image xlink:href="$src" xlink:type="simple">'
      '<svg:title>${_xmlEscape(alt)}</svg:title>'
      '</draw:image>'
      '</draw:frame>',
    );
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
        output.write('</text:h>\n');

      case 'p':
        if (ctx == _Ctx.paragraph) output.write('</text:p>\n');

      case 'blockquote':
        output.write('</text:p>\n');

      case 'ul':
        output.write('</text:list>\n');
      case 'ol':
        output.write('</text:list>\n');
      case 'li':
        output.write('</text:p></text:list-item>\n');

      case 'pre':
        break;
      case 'code':
        if (ctx == _Ctx.codeBlockBody) {
          // Code-blokregels zijn al geschreven in visitElementBefore.
        } else if (ctx == _Ctx.inlineCode) {
          _buf.write('</text:span>');
        }

      case 'strong':
      case 'b':
        _buf.write('</text:span>');
      case 'em':
      case 'i':
        _buf.write('</text:span>');
      case 'del':
      case 's':
        _buf.write('</text:span>');
      case 'a':
        if (ctx == _Ctx.link) _buf.write('</text:a>');

      case 'table':
        output.write('</table:table>\n');
      case 'thead':
        output.write('</table:table-header-rows>');
      case 'tbody':
        output.write('</table:table-rows>');
      case 'tr':
        output.write('</table:table-row>\n');
      case 'th':
      case 'td':
        _buf.write('</text:p></table:table-cell>');

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
  tableRow,
  tableCell,
}

/// XML-escape voor tekstinhoud: & < >.
String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// XML-escape voor attribuutwaarden: & < > " '.
String _xmlAttr(String s) =>
    _xmlEscape(s).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
