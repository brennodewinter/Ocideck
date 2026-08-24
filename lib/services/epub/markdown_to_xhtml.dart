// Markdown → XHTML-kernconverter voor ePub 3.
//
// Zet een GFM-Markdown-string om in een XHTML-fragment (geen <html>/<head>/
// <body> — dat leveren de EPUB-structuur in document_epub_export.dart). Deze
// kern is zuiver tekst-in, XHTML-uit, en headless: geen Flutter, geen IO.
//
// Hergebruikt de `markdown`-package (pubspec: `markdown: ^7.3.1`) als
// AST-parser — hetzelfde patroon als lib/services/latex/markdown_to_latex.dart
// en lib/utils/markdown_quill_codec.dart. Geen nieuwe dependency.
//
// XHTML-verschillen ten opzichte van de HTML-export (die `marked` in de browser
// rendert): self-closing tags (<br/>, <img/>), ge-escape'de entities, geen
// boolean attributen, en well-formed XML — een e-reader parseert strenger dan
// een browser.

import 'package:markdown/markdown.dart' as md;

import '../../utils/export_link.dart';
import '../../utils/footnotes.dart';
import '../document_timeline.dart';
import '../markdown_table_lines.dart';

/// Zet [markdown] (GFM) om in een XHTML-fragment.
///
/// De uitvoer is platte XHTML zonder documentomhulling. Bedoeld om in een
/// EPUB-XHTML-content-document ingebed te worden door de wrapper in
/// [buildDocumentExportEpub].
///
/// [chapterPageBreak] voegt een CSS `page-break-before: always` toe aan elke
/// H1 behalve de eerste — voor e-readers die dat ondersteunen.
/// [footnotesTitle] is de titel boven de notenlijst achterin (de converter
/// kent geen vertalingen).
String markdownToXhtml(
  String markdown, {
  bool chapterPageBreak = false,
  String footnotesTitle = 'Noten',
}) {
  if (markdown.trim().isEmpty) return '';

  // Voetnoten:zelfde aanpak als de HTML-export (footnotes_html.dart): de
  // verwijzing wordt een <sup> met sprong, de definities verdwijnen, en de
  // noten komen als genummerde lijst achteraan. De HTML-export gebruikt
  // `documentWithHtmlFootnotes` dat de markdown door `marked` rendert; hier
  // doen we het zelf met de `markdown`-package, maar de voetnoot-structuur
  // is hetzelfde.
  final notes = documentFootnotes(markdown);
  var source = stripFootnoteDefinitions(markdown);

  // Tijdlijnen: bescherm ze vóór de parse, net als de LaTeX-converter. Een
  // tijdlijn is een markdown-tabel met de timeline-marker, en de
  // markdown-package rendert die als een gewone tabel — wat technisch klopt
  // maar de semantiek verliest. Hier volstaat de gewone tabel-rendering: een
  // e-reader toont een tabel als een tabel, en de tijdlijn-marker blijft als
  // commentaar zichtbaar voor wie de bron kent.
  final timelines = _protectDocumentTimelines(source);
  source = timelines.source;

  for (final note in notes) {
    source = source.replaceAll(
      '[^${note.label}]',
      '<span class="ocideck-fnref" id="fnref-${note.number}">'
          '<a href="#fn-${note.number}">${note.number}</a></span>',
    );
  }

  // Inhoudsopgave: `<!-- toc -->` → een placeholder die na de conversie een
  // nav-element wordt. De markdown-package stript commentaar, dus vervang
  // vóór de parse — net als de LaTeX-converter.
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
  final visitor = _XhtmlNodeVisitor(chapterPageBreak: chapterPageBreak);
  for (final node in nodes) {
    node.accept(visitor);
  }

  var out = visitor.output.toString().replaceAll(
    tocSentinel,
    '<nav epub:type="toc" id="ocideck-toc"><h2>${_xmlEscape(footnotesTitle)}</h2></nav>',
  );

  // Tijdlijn-placeholders herstellen.
  for (var i = 0; i < timelines.xhtml.length; i++) {
    out = out.replaceAll('OCIDECKTIMELINE${i}END', timelines.xhtml[i]);
  }

  // Noten achteraan, als genummerde lijst —zelfde structuur als de HTML-export.
  if (notes.isNotEmpty) {
    out = '$out\n\n${_endnotesSection(notes, footnotesTitle)}';
  }

  return out.trimRight();
}

/// De noten achterin, als genummerde lijst onder een eigen kop.
String _endnotesSection(List<Footnote> notes, String title) {
  final buf = StringBuffer()
    ..writeln('<section class="ocideck-footnotes" epub:type="endnotes">')
    ..writeln('<h2>${_xmlEscape(title)}</h2>')
    ..writeln('<ol>');
  for (final note in notes) {
    buf
      ..write('<li id="fn-${note.number}">')
      ..write(_inlineXhtml(note.text))
      ..write(' <a class="ocideck-fnback" href="#fnref-${note.number}">↩</a>')
      ..writeln('</li>');
  }
  buf
    ..writeln('</ol>')
    ..write('</section>');
  return buf.toString();
}

/// De inline-markdown van een noot als XHTML — vet, cursief, code en links,
/// maar geen alinea's: een noot is één regel in een lijstitem.
String _inlineXhtml(String text) => md
    .markdownToHtml(
      text,
      inlineOnly: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    )
    .trim();

/// Bescherm tijdlijn-tabellen vóór de parse. De markdown-package rendert een
/// tijdlijn als een gewone tabel, wat voor ePub goed genoeg is — de
/// tijdlijn-marker blijft als HTML-commentaar zichtbaar.
({String source, List<String> xhtml}) _protectDocumentTimelines(String source) {
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
    // De tijdlijn wordt als gewone tabel gerenderd; de marker blijft als
    // commentaar erboven staan voor wie de bron kent.
    final buf = StringBuffer('<!-- timeline -->\n');
    buf.writeln('<table class="ocideck-timeline">');
    buf.writeln('<thead><tr>');
    for (final header in timeline.headers) {
      buf.write('<th>${_xmlEscape(header)}</th>');
    }
    buf.writeln('</tr></thead>');
    buf.writeln('<tbody>');
    for (final event in timeline.events) {
      buf.write('<tr>');
      buf.write('<td>${_inlineXhtml(event.marker)}</td>');
      buf.write('<td>${_inlineXhtml(event.event)}</td>');
      buf.write('<td>${_inlineXhtml(event.metadata ?? '')}</td>');
      buf.writeln('</tr>');
    }
    buf.writeln('</tbody></table>');
    output.add('OCIDECKTIMELINE${rendered.length}END');
    rendered.add(buf.toString());
    index = end;
  }
  return (source: output.join('\n'), xhtml: rendered);
}

class _XhtmlNodeVisitor implements md.NodeVisitor {
  _XhtmlNodeVisitor({this.chapterPageBreak = false});

  final StringBuffer output = StringBuffer();

  /// Of elk hoofdstuk (H1) op een nieuwe pagina begint (instelling).
  final bool chapterPageBreak;

  bool _seenChapter = false;

  /// Stack van context-vlaggen per open element.
  final List<_Ctx> _stack = [];

  bool get _inCodeBlock => _stack.any((c) => c == _Ctx.codeBlock);

  // XHTML-tabellen schrijven direct naar output — geen tussenbuffer nodig
  // (in tegenstelling tot LaTeX, waar cellen &-scheiding en \\-rij-einden
  // nodig hebben).
  StringBuffer get _buf => output;

  @override
  void visitText(md.Text text) {
    // De markdown-package met `encodeHtml: true` escaped al & < >, maar in
    // code-blokken staat de inhoud in <pre><code> en moet raw blijven — de
    // parser heeft het daar al ge-escape'd.
    _buf.write(text.text);
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      // ── Koppen ──
      case 'h1':
        if (chapterPageBreak && _seenChapter) {
          output.write(
            '<h1 style="page-break-before:always;break-before:page">',
          );
        } else {
          output.write('<h1>');
        }
        _seenChapter = true;
        _stack.add(_Ctx.heading);
      case 'h2':
        output.write('<h2>');
        _stack.add(_Ctx.heading);
      case 'h3':
        output.write('<h3>');
        _stack.add(_Ctx.heading);
      case 'h4':
        output.write('<h4>');
        _stack.add(_Ctx.heading);
      case 'h5':
        output.write('<h5>');
        _stack.add(_Ctx.heading);
      case 'h6':
        output.write('<h6>');
        _stack.add(_Ctx.heading);

      // ── Alinea's en blokken ──
      case 'p':
        output.write('<p>');
        _stack.add(_Ctx.paragraph);
      case 'blockquote':
        output.write('<blockquote>');
        _stack.add(_Ctx.blockquote);
      case 'hr':
        output.write('<hr/>');
        return false;

      // ── Lijsten ──
      case 'ul':
        output.write('<ul>');
        _stack.add(_Ctx.unorderedList);
      case 'ol':
        output.write('<ol');
        final start = element.attributes['start'];
        if (start != null && start != '1') {
          output.write(' start="$start"');
        }
        output.write('>');
        _stack.add(_Ctx.orderedList);
      case 'li':
        _visitListItem(element);
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
        _buf.write('<strong>');
        _stack.add(_Ctx.inline);
      case 'em':
      case 'i':
        _buf.write('<em>');
        _stack.add(_Ctx.inline);
      case 'del':
      case 's':
        _buf.write('<del>');
        _stack.add(_Ctx.inline);

      // ── Links en afbeeldingen ──
      case 'a':
        final href = safeExportLink(element.attributes['href']);
        if (href == null) {
          _stack.add(_Ctx.passThrough);
        } else {
          _buf.write('<a href="${_xmlAttr(href)}">');
          _stack.add(_Ctx.link);
        }
      case 'img':
        _visitImage(element);
        return false;

      // ── Regelonderbreking ──
      case 'br':
        _buf.write('<br/>');
        return false;

      // ── Tabellen (GFM) ──
      case 'table':
        _stack.add(_Ctx.table);
        output.write('<table>');
        return true;
      case 'thead':
        output.write('<thead>');
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tbody':
        output.write('<tbody>');
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tr':
        _stack.add(_Ctx.tableRow);
        output.write('<tr>');
        return true;
      case 'th':
      case 'td':
        _stack.add(_Ctx.tableCell);
        _buf.write('<${element.tag}');
        final align = element.attributes['align'];
        if (align != null) {
          _buf.write(' style="text-align:$align"');
        }
        _buf.write('>');
        return true;

      default:
        _stack.add(_Ctx.passThrough);
    }
    return true;
  }

  void _visitListItem(md.Element element) {
    final isTask =
        element.attributes['class']?.contains('task-list-item') ?? false;
    final checked = element.children?.whereType<md.Element>().any(
      (child) => child.tag == 'input' && child.attributes['checked'] != null,
    );
    if (!isTask) {
      output.write('<li>');
    } else {
      output.write(
        checked == true
            ? '<li class="task-list-item"><input type="checkbox" checked="checked" disabled="disabled"/> '
            : '<li class="task-list-item"><input type="checkbox" disabled="disabled"/> ',
      );
    }
  }

  bool _visitCode(md.Element element) {
    if (_inCodeBlock) {
      final lang =
          element.attributes['class']?.replaceAll('language-', '') ?? '';
      output.write('<pre><code');
      if (lang.isNotEmpty) output.write(' class="language-$lang"');
      output.write('>');
      _stack.add(_Ctx.codeBlockBody);
    } else {
      _buf.write('<code>');
      _stack.add(_Ctx.inlineCode);
    }
    return true;
  }

  void _visitImage(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    // Afbeeldingen worden door de EPUB-export herwerkt: data-URI's worden
    // naar aparte bestanden geschreven en het src-attribuut wordt
    // gerebaseerd. Hier schrijven we het originele src; de EPUB-builder
    // vervangt het later.
    _buf.write('<img src="${_xmlAttr(src)}" alt="${_xmlAttr(alt)}"/>');
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
        output.write('</${element.tag}>\n\n');

      case 'p':
        if (ctx == _Ctx.paragraph) output.write('</p>\n\n');

      case 'blockquote':
        output.write('</blockquote>\n');

      case 'ul':
        output.write('</ul>\n');
      case 'ol':
        output.write('</ol>\n');
      case 'li':
        output.write('</li>\n');

      case 'pre':
        break;
      case 'code':
        if (ctx == _Ctx.codeBlockBody) {
          output.write('</code></pre>\n');
        } else if (ctx == _Ctx.inlineCode) {
          _buf.write('</code>');
        }

      case 'strong':
      case 'b':
        _buf.write('</strong>');
      case 'em':
      case 'i':
        _buf.write('</em>');
      case 'del':
      case 's':
        _buf.write('</del>');
      case 'a':
        if (ctx == _Ctx.link) _buf.write('</a>');

      case 'table':
        output.write('</table>\n');
      case 'thead':
        output.write('</thead>');
      case 'tbody':
        output.write('</tbody>');
      case 'tr':
        output.write('</tr>\n');
      case 'th':
      case 'td':
        _buf.write('</${element.tag}>');

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

/// XML-escape voor tekstinhoud: & < >. De markdown-package met
/// `encodeHtml: true` doet dit al voor de meeste tekst, maar tijdlijn-headers
/// en noot-titels gaan er rechtstreeks doorheen.
String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// XML-escape voor attribuutwaarden: & < > " '.
String _xmlAttr(String s) =>
    _xmlEscape(s).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
