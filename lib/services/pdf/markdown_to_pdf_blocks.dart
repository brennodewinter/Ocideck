// Markdown → de tussenvorm van de PDF-export.
//
// Zusje van `markdown_to_latex.dart`, en met opzet langs dezelfde lijnen
// gebouwd: dezelfde `markdown`-package als parser, dezelfde Markdown-constructen,
// dezelfde afspraak dat een `---` in een document een pagina-einde is en geen
// streep. Waar de LaTeX-converter een string schrijft, levert deze de getypeerde
// blokken uit `document_pdf_blocks.dart` op — zie daar waarom.
//
// Wat deze laag NIET doet: tekenen, meten, pagineren of een bestand aanraken.
// Tekst in, blokken uit. Daardoor is elke beslissing hier met een gewone
// unit-test vast te leggen.

import 'package:markdown/markdown.dart' as md;

import '../../utils/footnotes.dart';
import '../document_timeline.dart';
import 'document_pdf_blocks.dart';

/// Zet [markdown] (GFM) om in de blokken waaruit de PDF wordt opgebouwd.
///
/// [footnotesTitle] is de kop boven de notenlijst achterin. Die komt van de
/// aanroeper: deze converter kent geen vertalingen en is zuiver tekst-in,
/// blokken-uit.
///
/// Voetnoten landen áchterin, ook wanneer het document om onderaan-de-bladzijde
/// vraagt. Dat is geen vergeetachtigheid maar de aard van het pagineren: welke
/// noot op welk blad hoort, blijkt pas ná de opmaak, en dan staat de bladzijde
/// er al. Dezelfde grens gold al voor de HTML-route (KNOWN_LIMITATIONS.md); wie
/// noten écht onderaan het blad wil, exporteert naar LaTeX.
List<PdfBlock> markdownToPdfBlocks(
  String markdown, {
  bool chapterPageBreak = false,
  String footnotesTitle = 'Noten',
}) {
  if (markdown.trim().isEmpty) return const [];

  // Voetnoten vóór de parse eruit halen, om dezelfde reden als bij LaTeX: als
  // definitie-regels zou de parser er losse alinea's van maken, onderin het
  // document, zonder verband met hun merkteken.
  final notes = documentFootnotes(markdown);
  var source = stripFootnoteDefinitions(markdown);
  source = _stripTimelineMarkers(source);
  for (final note in notes) {
    source = source.replaceAll(
      '[^${note.label}]',
      _footnoteSentinel(note.number),
    );
  }
  // De inhoudsopgave-marker is een HTML-commentaar; de parser gooit die weg.
  // Een sentinel-alinea overleeft de parse wél en wordt hieronder een
  // [PdfTocBlock].
  //
  // De regel eromheen mag alleen spaties en tabs bevatten, geen `\s`: dat
  // laatste vreet ook de lege regel eronder op, en dan plakt de marker aan de
  // alinea die erop volgt — één alinea die met de marker begint in plaats van
  // een inhoudsopgave met tekst eronder. De LaTeX-converter heeft daar geen
  // last van omdat die zijn sentinel achteraf in de úítvoer vervangt; hier is de
  // marker een blok en moet hij dus ook als los blok de parser uit komen.
  final withToc = source.replaceAll(
    RegExp(r'^<!-- toc -->[ \t]*$', multiLine: true),
    '\n$_tocSentinel\n',
  );

  final document = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parse(withToc);
  final converter = _PdfBlockConverter(chapterPageBreak: chapterPageBreak);
  final blocks = converter.blocks(nodes);

  if (notes.isEmpty) return blocks;
  return [...blocks, ..._endnoteBlocks(notes, footnotesTitle)];
}

/// De marker die `<!-- toc -->` vervangt tijdens de parse. Geen leestekens die
/// Markdown zelf betekenis geeft, zodat er onderweg niets aan verandert.
const _tocSentinel = 'OCIDECKTABLEOFCONTENTSMARKER';

String _footnoteSentinel(int number) => 'OCIDECKFOOTNOTE${number}END';

final _footnoteSentinelPattern = RegExp(r'OCIDECKFOOTNOTE(\d+)END');

/// Haalt de tijdlijn-markers weg en laat de tabel eronder staan.
///
/// Een tijdlijn ís in de bron een tabel met een markerregel erboven
/// (`document_timeline.dart`). De PDF tekent hem als gewone tabel: alle inhoud
/// blijft, alleen de tijdbalk-vorm van het scherm niet. Zonder het weghalen van
/// de marker zou het HTML-commentaar als losse alinea in de PDF landen.
String _stripTimelineMarkers(String source) => source.replaceAll(
  RegExp('^${RegExp.escape(documentTimelineMarker)}\\s*\$', multiLine: true),
  '',
);

/// De notenlijst achterin: een kop, en per noot een alinea die met zijn nummer
/// begint.
List<PdfBlock> _endnoteBlocks(List<Footnote> notes, String title) {
  final blocks = <PdfBlock>[PdfHeadingBlock(2, [PdfSpan(title)], title)];
  for (final note in notes) {
    blocks.add(
      PdfParagraphBlock([
        PdfSpan('${note.number}. ', bold: true),
        ..._inlineOf(note.text),
      ]),
    );
  }
  return blocks;
}

/// Zet een losse regel Markdown om in opgemaakte stukken tekst. Gebruikt voor
/// de tekst van een voetnoot, die zelf weer cursief of een link kan bevatten.
List<PdfSpan> _inlineOf(String markdown) {
  final document = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parseInline(markdown);
  final converter = _PdfBlockConverter(chapterPageBreak: false);
  return converter.spans(nodes, const PdfSpan(''));
}

/// Loopt de Markdown-boom af en bouwt er blokken van.
class _PdfBlockConverter {
  _PdfBlockConverter({required this.chapterPageBreak});

  /// Of elk hoofdstuk (een H1) op een nieuw blad begint — de instelling
  /// *Nieuw hoofdstuk op een nieuwe pagina*.
  final bool chapterPageBreak;

  /// Of we al een hoofdstuk zagen. Het eerste krijgt geen pagina-einde, anders
  /// opent het document met een leeg blad.
  bool _seenChapter = false;

  List<PdfBlock> blocks(List<md.Node> nodes) {
    final out = <PdfBlock>[];
    for (final node in nodes) {
      _block(node, out);
    }
    return out;
  }

  void _block(md.Node node, List<PdfBlock> out) {
    if (node is md.Text) {
      // Losse tekst tussen blokken door — komt voor bij witruimte in de boom.
      if (node.text.trim().isEmpty) return;
      out.add(PdfParagraphBlock([PdfSpan(node.text)]));
      return;
    }
    if (node is! md.Element) return;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _heading(node, out);
      case 'p':
        _paragraph(node, out);
      case 'hr':
        // Een thematische breuk is in een document een nieuw blad, geen streep
        // (DOCUMENT_MODE.md §13) — gelijk aan de `\newpage` van de LaTeX-export.
        out.add(const PdfPageBreakBlock());
      case 'blockquote':
        out.add(PdfQuoteBlock(blocks(node.children ?? const [])));
      case 'ul':
        out.add(_list(node, ordered: false));
      case 'ol':
        out.add(_list(node, ordered: true));
      case 'pre':
        _codeBlock(node, out);
      case 'table':
        _table(node, out);
      case 'img':
        out.add(_image(node));
      default:
        // Onbekend blok: laat de inhoud niet vallen, maar behandel de kinderen
        // alsof ze op dit niveau stonden. Stil weglaten is in een export het
        // ergste wat er kan gebeuren.
        final children = node.children;
        if (children != null) out.addAll(blocks(children));
    }
  }

  void _heading(md.Element node, List<PdfBlock> out) {
    final level = int.parse(node.tag.substring(1));
    if (level == 1) {
      if (chapterPageBreak && _seenChapter) out.add(const PdfPageBreakBlock());
      _seenChapter = true;
    }
    final spans = _spansOf(node);
    out.add(PdfHeadingBlock(level, spans, _plain(spans)));
  }

  void _paragraph(md.Element node, List<PdfBlock> out) {
    // Een alinea die alleen uit een afbeelding bestaat is in een document een
    // eigen blok, geen regel tekst met een plaatje erin.
    final children = node.children ?? const [];
    final images = children.whereType<md.Element>().where((e) => e.tag == 'img');
    if (images.length == 1 && _isOnlyChild(children)) {
      out.add(_image(images.first));
      return;
    }
    final spans = _spansOf(node);
    if (spans.length == 1 && spans.first.text.trim() == _tocSentinel) {
      out.add(const PdfTocBlock());
      return;
    }
    if (spans.every((s) => s.text.trim().isEmpty)) return;
    out.add(PdfParagraphBlock(spans));
  }

  /// Of de alinea buiten deze ene afbeelding niets dan witruimte bevat.
  bool _isOnlyChild(List<md.Node> children) => children.every(
    (c) =>
        (c is md.Element && c.tag == 'img') ||
        (c is md.Text && c.text.trim().isEmpty),
  );

  PdfListBlock _list(md.Element node, {required bool ordered}) {
    final items = <PdfListItem>[];
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') continue;
      items.add(_listItem(child));
    }
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    return PdfListBlock(items, ordered: ordered, startNumber: start);
  }

  PdfListItem _listItem(md.Element node) {
    final children = node.children ?? const <md.Node>[];
    final isTask =
        node.attributes['class']?.contains('task-list-item') ?? false;
    bool? checked;
    final kept = <md.Node>[];
    for (final child in children) {
      if (child is md.Element && child.tag == 'input') {
        checked = child.attributes['checked'] != null;
        continue;
      }
      kept.add(child);
    }
    // Een 'strak' lijstpunt draagt zijn tekst rechtstreeks; een 'los' punt heeft
    // er een <p> omheen. Beide moeten dezelfde alinea opleveren.
    final blocks = <PdfBlock>[];
    final loose = <md.Node>[];
    for (final child in kept) {
      if (child is md.Element && _isBlockTag(child.tag)) {
        if (loose.isNotEmpty) {
          blocks.add(PdfParagraphBlock(spans(loose, const PdfSpan(''))));
          loose.clear();
        }
        _block(child, blocks);
      } else {
        loose.add(child);
      }
    }
    if (loose.isNotEmpty) {
      final inline = spans(loose, const PdfSpan(''));
      if (inline.any((s) => s.text.trim().isNotEmpty)) {
        blocks.add(PdfParagraphBlock(inline));
      }
    }
    return PdfListItem(blocks, checked: isTask ? (checked ?? false) : null);
  }

  static bool _isBlockTag(String tag) => const {
    'p',
    'ul',
    'ol',
    'pre',
    'blockquote',
    'table',
    'hr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  }.contains(tag);

  void _codeBlock(md.Element node, List<PdfBlock> out) {
    final code = node.children?.whereType<md.Element>().firstOrNull;
    final text = _rawText(code ?? node);
    final language = code?.attributes['class']
        ?.replaceAll('language-', '')
        .trim();
    // Mermaid en grafiekblokken kan een PDF niet tekenen — de HTML-export laat
    // daar een JavaScript-laag op los die hier niet bestaat. Ze gaan letterlijk
    // mee, met een aanduiding erboven, precies zoals de LaTeX-export ze als
    // codeblok laat staan.
    final kind = switch (language) {
      'mermaid' => PdfVerbatimKind.mermaid,
      'chart' => PdfVerbatimKind.chart,
      _ => null,
    };
    if (kind != null) {
      out.add(PdfVerbatimBlock(text, kind: kind));
      return;
    }
    out.add(
      PdfCodeBlock(
        text,
        language: language == null || language.isEmpty ? null : language,
      ),
    );
  }

  void _table(md.Element node, List<PdfBlock> out) {
    final rows = <List<List<PdfSpan>>>[];
    var hasHeader = false;
    List<PdfColumnAlignment>? alignments;

    void readRow(md.Element row, {required bool header}) {
      final cells = <List<PdfSpan>>[];
      final rowAlignments = <PdfColumnAlignment>[];
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is! md.Element) continue;
        if (cell.tag != 'th' && cell.tag != 'td') continue;
        cells.add(_spansOf(cell, base: PdfSpan('', bold: header)));
        rowAlignments.add(_alignmentOf(cell));
      }
      if (cells.isEmpty) return;
      if (header) hasHeader = true;
      alignments ??= rowAlignments;
      rows.add(cells);
    }

    void readSection(md.Element section, {required bool header}) {
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is md.Element && row.tag == 'tr') readRow(row, header: header);
      }
    }

    for (final section in node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      switch (section.tag) {
        case 'thead':
          readSection(section, header: true);
        case 'tbody':
          readSection(section, header: false);
        case 'tr':
          // Een tabel zonder thead/tbody-omhulsel: de eerste rij is de koprij,
          // net als GFM hem leest.
          readRow(section, header: rows.isEmpty);
      }
    }
    if (rows.isEmpty) return;
    out.add(PdfTableBlock(rows, hasHeader: hasHeader, alignments: alignments));
  }

  /// De uitlijning die de scheidingsrij van een GFM-tabel voorschrijft.
  ///
  /// De `markdown`-package schrijft die als `align="center"` op de cel — niet
  /// als `style="text-align: …"`, waar een CSS-reflex naar grijpt. Op die
  /// verkeerde aanname stond elke kolom links, ook de kolom met bedragen die
  /// om rechts vroeg.
  static PdfColumnAlignment _alignmentOf(md.Element cell) =>
      switch (cell.attributes['align']) {
        'right' => PdfColumnAlignment.right,
        'center' => PdfColumnAlignment.center,
        _ => PdfColumnAlignment.left,
      };

  PdfImageBlock _image(md.Element node) => PdfImageBlock(
    node.attributes['src'] ?? '',
    alt: node.attributes['alt'] ?? '',
  );

  List<PdfSpan> _spansOf(md.Element node, {PdfSpan? base}) =>
      spans(node.children ?? const [], base ?? const PdfSpan(''));

  /// Platten van de opmaakboom tot een rij stukken tekst, elk met precies één
  /// stijl. [inherited] draagt de opmaak van de omhullende elementen mee.
  List<PdfSpan> spans(List<md.Node> nodes, PdfSpan inherited) {
    final out = <PdfSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        _textSpans(node.text, inherited, out);
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'strong':
        case 'b':
          out.addAll(spans(node.children ?? const [], inherited.copyWith(bold: true)));
        case 'em':
        case 'i':
          out.addAll(
            spans(node.children ?? const [], inherited.copyWith(italic: true)),
          );
        case 'del':
        case 's':
          out.addAll(
            spans(
              node.children ?? const [],
              inherited.copyWith(strikeThrough: true),
            ),
          );
        case 'code':
          out.add(inherited.copyWith(text: _rawText(node), code: true));
        case 'a':
          out.addAll(
            spans(
              node.children ?? const [],
              inherited.copyWith(href: node.attributes['href'] ?? ''),
            ),
          );
        case 'br':
          out.add(inherited.copyWith(text: '\n'));
        case 'img':
          // Een afbeelding midden in een regel kan een PDF-alinea niet dragen;
          // de beschrijving houdt de betekenis vast in plaats van hem te laten
          // vallen.
          final alt = node.attributes['alt'] ?? '';
          if (alt.trim().isNotEmpty) {
            out.add(inherited.copyWith(text: alt, italic: true));
          }
        default:
          out.addAll(spans(node.children ?? const [], inherited));
      }
    }
    return out;
  }

  /// Knipt de voetnoot-merktekens uit de tekst en maakt er hoger geplaatste
  /// nummers van.
  void _textSpans(String text, PdfSpan inherited, List<PdfSpan> out) {
    var index = 0;
    for (final match in _footnoteSentinelPattern.allMatches(text)) {
      if (match.start > index) {
        out.add(inherited.copyWith(text: text.substring(index, match.start)));
      }
      out.add(
        inherited.copyWith(text: match.group(1)!, superscript: true, href: null),
      );
      index = match.end;
    }
    if (index < text.length) {
      out.add(inherited.copyWith(text: text.substring(index)));
    }
  }

  /// De letterlijke tekst onder een knoop, zonder opmaak.
  static String _rawText(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      return (node.children ?? const <md.Node>[]).map(_rawText).join();
    }
    return '';
  }
}

/// De platte tekst van een rij stukken — voor de bladwijzerboom en de
/// inhoudsopgave, die geen opmaak kennen.
String _plain(List<PdfSpan> spans) =>
    spans.map((s) => s.text).join().replaceAll(RegExp(r'\s+'), ' ').trim();
