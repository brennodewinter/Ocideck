// De tussenvorm uit `document_pdf_blocks.dart`, getekend als PDF-widgets.
//
// Bewust de dunne laag van de twee: alle beslissingen zijn al genomen — hier
// staat alleen nog hoe een kop, een tabel of een citaat eruitziet. Dat is de
// afspraak die de PDF-export toetsbaar houdt; zie de kop van
// `document_pdf_blocks.dart`.

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../models/settings.dart' show TableBorderStyle;
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';
import 'document_pdf_style.dart';

/// Eén kop zoals de inhoudsopgave en de bladwijzerboom hem kennen.
class PdfHeadingEntry {
  const PdfHeadingEntry(this.index, this.level, this.title);

  /// De plek in het document, oplopend vanaf nul. Tevens de ankernaam.
  final int index;
  final int level;
  final String title;

  /// De naam waarmee een sprong in de PDF naar deze kop verwijst.
  String get anchor => 'ocideck-kop-$index';
}

/// Zoekt alle koppen op vóórdat er iets getekend is.
///
/// De inhoudsopgave staat vooraan maar gaat over wat verderop komt; zonder deze
/// voorafgaande blik zou hij alleen de koppen kennen die er al stonden.
List<PdfHeadingEntry> headingEntriesOf(List<PdfBlock> blocks) {
  final entries = <PdfHeadingEntry>[];
  for (final block in blocks) {
    if (block is! PdfHeadingBlock) continue;
    entries.add(
      PdfHeadingEntry(entries.length, block.level, block.outlineText),
    );
  }
  return entries;
}

/// Tekent de blokken van één document.
class DocumentPdfWidgets {
  DocumentPdfWidgets({
    required this.style,
    required this.fonts,
    required this.headings,
    required this.tocTitle,
    required this.verbatimLabel,
    this.images = const {},
    this.headingPages = const {},
    this.onHeadingLaidOut,
  });

  final DocumentPdfStyle style;
  final DocumentPdfFonts fonts;

  /// Alle koppen in leesvolgorde, voor de inhoudsopgave en de ankers.
  final List<PdfHeadingEntry> headings;

  /// De kop bóven de inhoudsopgave. Komt van de aanroeper; deze laag kent geen
  /// vertalingen.
  final String tocTitle;

  /// De aanduiding boven een blok dat letterlijk wordt weergegeven — ook een
  /// vertaalde tekst van de aanroeper.
  final String Function(PdfVerbatimKind kind) verbatimLabel;

  /// De bytes per afbeeldingsbron. Een PDF verwijst niet naar bestanden buiten
  /// zichzelf: wat er niet in zit, staat er niet in.
  final Map<String, Uint8List> images;

  /// Op welk blad elke kop landde. Leeg in de eerste opmaakronde — dan blijft
  /// de kolom met bladzijdenummers leeg maar even breed, zodat de tweede ronde
  /// exact dezelfde opmaak oplevert.
  final Map<int, int> headingPages;

  /// Aangeroepen zodra een kop is opgemaakt, met het blad waarop hij landde.
  /// Zo weet de tweede ronde wat de eerste heeft uitgerekend.
  final void Function(int index, int page)? onHeadingLaidOut;

  int _headingCursor = 0;

  /// Zet [blocks] om in de widgets van de doorlopende bladzijdestroom.
  ///
  /// [tight] geldt binnen een lijstpunt. Een alinea in de lopende tekst wil lucht
  /// onder zich; dezelfde lucht tussen de punten van een opsomming trekt de lijst
  /// uit elkaar tot hij niet meer als één lijst leest.
  List<pw.Widget> build(List<PdfBlock> blocks, {bool tight = false}) {
    final widgets = <pw.Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final next = index + 1 < blocks.length ? blocks[index + 1] : null;
      if (block is PdfHeadingBlock && next != null && _bindsToHeading(next)) {
        widgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [_heading(block), _widget(next, tight: tight)],
            ),
          ),
        );
        index++;
        continue;
      }
      widgets.add(_widget(block, tight: tight));
    }
    return widgets;
  }

  /// Of het blok ná een kop met die kop mee de bladzijde over moet.
  ///
  /// Een kop die alleen onderaan een blad achterblijft kondigt niets meer aan.
  /// De HTML-afdruk lost dat op met `break-after: avoid`; `MultiPage` kent zoiets
  /// niet, dus binden we de kop hier zelf aan wat erop volgt — in een
  /// [pw.Inseparable] die niet mag breken, zodat het paar in zijn geheel
  /// opschuift wanneer het onderaan niet meer past.
  ///
  /// **Waarom een grens op de lengte.** Een niet-brekend paar dat hóger is dan
  /// een bladzijde kan `MultiPage` nergens kwijt en dán werpt hij een fout: de
  /// export zou stukslaan op een lange alinea. De grens hieronder is daarom geen
  /// schatting van de hoogte maar een ruime afstand tot de afgrond — een A4 op
  /// 11 punt draagt ruwweg drieduizend tekens, en dit bindt tot een derde
  /// daarvan. Wie de maat verkleint of het lettertype vergroot, blijft daarmee
  /// nog steeds ver aan de goede kant.
  bool _bindsToHeading(PdfBlock block) => switch (block) {
    PdfParagraphBlock(:final spans) =>
      spans.fold<int>(0, (sum, s) => sum + s.text.length) <= _keepTogetherChars,
    PdfCodeBlock(:final code) => code.length <= _keepTogetherChars,
    PdfVerbatimBlock(:final source) => source.length <= _keepTogetherChars,
    PdfListBlock(:final items) =>
      items.length <= 5 && _listTextLength(items) <= _keepTogetherChars,
    _ => false,
  };

  static const _keepTogetherChars = 1000;

  static int _listTextLength(List<PdfListItem> items) {
    var total = 0;
    for (final item in items) {
      for (final block in item.blocks) {
        if (block is PdfParagraphBlock) {
          for (final span in block.spans) {
            total += span.text.length;
          }
        }
      }
    }
    return total;
  }

  pw.Widget _widget(PdfBlock block, {required bool tight}) => switch (block) {
    PdfHeadingBlock() => _heading(block),
    PdfParagraphBlock() => _paragraph(block, tight: tight),
    PdfListBlock() => _list(block),
    PdfQuoteBlock() => _quote(block),
    PdfCodeBlock() => _code(block.code, language: block.language),
    PdfVerbatimBlock() => _verbatim(block),
    PdfTableBlock() => _table(block),
    PdfImageBlock() => _image(block),
    PdfPageBreakBlock() => pw.NewPage(),
    PdfTocBlock() => _toc(),
  };

  // ── Koppen ───────────────────────────────────────────────────────────────

  pw.Widget _heading(PdfHeadingBlock block) {
    final entry = _headingCursor < headings.length
        ? headings[_headingCursor]
        : PdfHeadingEntry(_headingCursor, block.level, block.outlineText);
    _headingCursor++;
    final size = style.headingSize(block.level);
    final text = pw.RichText(
      text: pw.TextSpan(
        style: _baseStyle.copyWith(
          fontSize: size,
          fontWeight: pw.FontWeight.bold,
          lineSpacing: size * 0.2,
        ),
        children: _spans(block.spans, size: size),
      ),
    );
    return pw.Container(
      margin: pw.EdgeInsets.only(
        top: style.headingSpaceBefore(block.level),
        bottom: style.headingSpaceAfter,
      ),
      // Een kop hoort niet alleen onderaan een blad achter te blijven. Het
      // `MultiPage`-model kent geen "houd bij het volgende", dus dit is het
      // dichtste wat er is: de kop mag zelf niet breken.
      child: pw.Outline(
        name: entry.anchor,
        title: entry.title,
        level: (block.level - 1).clamp(0, 5),
        child: _recordPage(entry.index, text),
      ),
    );
  }

  /// Wikkelt een kop zo in dat we tijdens het opmaken zien op welk blad hij
  /// landt — de enige manier om een inhoudsopgave met bladzijdenummers te
  /// vullen zonder het document te meten voordat het bestaat.
  pw.Widget _recordPage(int index, pw.Widget child) {
    final record = onHeadingLaidOut;
    if (record == null) return child;
    return pw.DelayedWidget(
      build: (context) {
        record(index, context.pageNumber);
        return child;
      },
    );
  }

  // ── Alinea's en citaten ──────────────────────────────────────────────────

  pw.Widget _paragraph(PdfParagraphBlock block, {bool tight = false}) =>
      pw.Container(
    margin: pw.EdgeInsets.only(
      bottom: tight ? style.bodyFontSize * 0.15 : style.blockSpacing,
    ),
    child: pw.RichText(
      textAlign: pw.TextAlign.left,
      text: pw.TextSpan(style: _baseStyle, children: _spans(block.spans)),
    ),
  );

  pw.Widget _quote(PdfQuoteBlock block) => pw.Container(
    margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
    padding: pw.EdgeInsets.only(left: style.indent, top: 2, bottom: 2),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: style.accentColor, width: 2),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: build(block.blocks),
    ),
  );

  // ── Lijsten ──────────────────────────────────────────────────────────────

  pw.Widget _list(PdfListBlock block) {
    final rows = <pw.Widget>[];
    var number = block.startNumber;
    for (final item in block.items) {
      rows.add(_listItem(item, marker: block.ordered ? '$number.' : null));
      if (block.ordered) number++;
    }
    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  pw.Widget _listItem(PdfListItem item, {String? marker}) => pw.Container(
    margin: pw.EdgeInsets.only(bottom: style.bodyFontSize * 0.25),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: style.indent, child: _marker(item, marker)),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: build(item.blocks, tight: true),
          ),
        ),
      ],
    ),
  );

  /// Het merkteken vóór een lijstpunt: een nummer, een vinkvakje of een bolletje.
  ///
  /// Het vakje van een takenlijst wordt getékend en niet gezet. Een aangevinkt
  /// vakje is in Unicode een teken (`☑`) dat de standaardsneden niet hebben en
  /// dat ook in het terugvalfont ontbreekt; als tekst zou het een leeg blokje
  /// worden — precies het stille verlies waar deze export voor waakt.
  pw.Widget _marker(PdfListItem item, String? ordered) {
    final size = style.bodyFontSize;
    if (item.checked != null) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: size * 0.2, right: size * 0.4),
        child: pw.Align(
          alignment: pw.Alignment.topRight,
          child: pw.Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: style.textColor, width: 0.7),
              color: item.checked! ? style.accentColor : null,
            ),
          ),
        ),
      );
    }
    if (ordered != null) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(right: size * 0.4),
        child: pw.Align(
          alignment: pw.Alignment.topRight,
          child: pw.Text(ordered, style: _baseStyle),
        ),
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: size * 0.42, right: size * 0.45),
      child: pw.Align(
        alignment: pw.Alignment.topRight,
        child: pw.Container(
          width: size * 0.22,
          height: size * 0.22,
          decoration: pw.BoxDecoration(
            color: style.textColor,
            shape: pw.BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // ── Code en letterlijke blokken ──────────────────────────────────────────

  pw.Widget _code(String code, {String? language}) => pw.Container(
    width: double.infinity,
    margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
    padding: pw.EdgeInsets.all(style.bodyFontSize * 0.6),
    decoration: pw.BoxDecoration(
      color: style.codeBackground,
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Text(
      code.trimRight(),
      style: pw.TextStyle(
        font: fonts.mono,
        fontFallback: fonts.fallback,
        fontSize: style.monoSize,
        color: style.codeText,
        lineSpacing: style.monoSize * 0.3,
      ),
    ),
  );

  /// Een blok dat de PDF niet zelf kan tekenen, met een eerlijke aanduiding
  /// erboven en de bron eronder. Zie [PdfVerbatimBlock] voor het waarom.
  pw.Widget _verbatim(PdfVerbatimBlock block) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        verbatimLabel(block.kind),
        style: _baseStyle.copyWith(
          fontSize: style.bandSize,
          color: style.bandTextColor,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
      pw.SizedBox(height: style.bodyFontSize * 0.2),
      _code(block.source),
    ],
  );

  // ── Tabellen ─────────────────────────────────────────────────────────────

  pw.Widget _table(PdfTableBlock block) {
    final rows = <pw.TableRow>[];
    for (var index = 0; index < block.rows.length; index++) {
      final isHeader = block.hasHeader && index == 0;
      final zebra = !isHeader && index.isEven ? style.tableZebra : null;
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isHeader ? style.tableHeaderBackground : zebra,
          ),
          children: [
            for (var column = 0; column < block.rows[index].length; column++)
              _cell(block, row: index, column: column, header: isHeader),
          ],
        ),
      );
    }
    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
      child: pw.Table(border: _tableBorder(), children: rows),
    );
  }

  pw.Widget _cell(
    PdfTableBlock block, {
    required int row,
    required int column,
    required bool header,
  }) {
    final alignments = block.alignments;
    final alignment = alignments != null && column < alignments.length
        ? alignments[column]
        : PdfColumnAlignment.left;
    return pw.Padding(
      padding: pw.EdgeInsets.all(style.tableCellPadding),
      child: pw.RichText(
        textAlign: switch (alignment) {
          PdfColumnAlignment.left => pw.TextAlign.left,
          PdfColumnAlignment.center => pw.TextAlign.center,
          PdfColumnAlignment.right => pw.TextAlign.right,
        },
        text: pw.TextSpan(
          style: _baseStyle.copyWith(
            color: header ? style.tableHeaderText : style.tableText,
          ),
          children: _spans(block.rows[row][column]),
        ),
      ),
    );
  }

  /// De randvorm van tabellen, gelijk aan wat het stijlprofiel op het scherm en
  /// in de LaTeX-export doet: omkaderd, alleen horizontale lijnen, of niets.
  pw.TableBorder? _tableBorder() => switch (style.tableBorderStyle) {
    TableBorderStyle.boxed => pw.TableBorder.all(
      color: style.tableBorderColor,
      width: 0.5,
    ),
    TableBorderStyle.lined => pw.TableBorder.symmetric(
      inside: pw.BorderSide(color: style.tableBorderColor, width: 0.5),
      outside: pw.BorderSide(color: style.tableBorderColor, width: 0.5),
    ),
    TableBorderStyle.none => null,
  };

  // ── Afbeeldingen ─────────────────────────────────────────────────────────

  pw.Widget _image(PdfImageBlock block) {
    final bytes = images[block.source];
    if (bytes == null) {
      // Onvindbaar of onleesbaar: zeg dát, met de beschrijving die de auteur
      // gaf. Een leeg gat laat de lezer denken dat er niets hoorde te staan.
      return pw.Container(
        margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
        child: pw.Text(
          block.alt.trim().isEmpty ? block.source : block.alt,
          style: _baseStyle.copyWith(
            fontStyle: pw.FontStyle.italic,
            color: style.bandTextColor,
          ),
        ),
      );
    }
    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
      alignment: pw.Alignment.center,
      child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
    );
  }

  // ── Inhoudsopgave ────────────────────────────────────────────────────────

  pw.Widget _toc() => pw.Container(
    margin: pw.EdgeInsets.only(bottom: style.blockSpacing),
    child: pw.Column(
      // Uitrekken en niet links uitlijnen: bij `start` krijgt elke regel losse
      // breedtebeperkingen en krimpt hij tot zijn eigen inhoud, waardoor de
      // bladzijdenummers als een rafelrand onder elkaar komen te staan in plaats
      // van in één kolom tegen de rechtermarge.
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final entry in headings) _tocEntry(entry),
      ],
    ),
  );

  /// Eén regel van de inhoudsopgave: de kop links, het bladzijdenummer rechts.
  ///
  /// **Waarom geen stippellijn ertussen.** Die vraagt om een meerekkend vak
  /// tussen titel en nummer, en de flex-verdeling van `package:pdf` deelt de
  /// vrije ruimte dan tussen de titel én dat vak — waarna de regel korter
  /// uitvalt dan de bladspiegel en de nummers als een rafelrand onder elkaar
  /// komen te staan. Het alternatief (de titel niet-meerekkend maken) haalt die
  /// rafelrand weg maar zet er een ergere fout voor terug: een kop die langer is
  /// dan de regel loopt dan buiten het blad, en dat ziet een test met
  /// verwachtingswaarden niet. Een meerekkende titel die netjes afbreekt en een
  /// nummer in een vaste kolom kan geen van beide.
  pw.Widget _tocEntry(PdfHeadingEntry entry) {
    final page = headingPages[entry.index];
    return pw.Link(
      destination: entry.anchor,
      child: pw.Container(
        margin: pw.EdgeInsets.only(bottom: style.bodyFontSize * 0.22),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: style.indent * (entry.level - 1)),
            pw.Expanded(
              child: pw.Text(
                entry.title,
                style: _baseStyle.copyWith(
                  fontWeight: entry.level == 1
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.SizedBox(width: style.bodyFontSize),
            // In de eerste ronde is het nummer nog niet bekend. De kolom blijft
            // dan even breed, zodat de tweede ronde niet anders pagineert dan de
            // eerste — anders zou het nummer verwijzen naar het blad van vóór
            // het invullen.
            pw.SizedBox(
              width: style.bodyFontSize * 1.8,
              child: pw.Text(
                page?.toString() ?? '',
                textAlign: pw.TextAlign.right,
                style: _baseStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tekst ────────────────────────────────────────────────────────────────

  pw.TextStyle get _baseStyle => pw.TextStyle(
    font: fonts.base,
    fontBold: fonts.bold,
    fontItalic: fonts.italic,
    fontBoldItalic: fonts.boldItalic,
    fontFallback: fonts.fallback,
    fontSize: style.bodyFontSize,
    color: style.textColor,
    lineSpacing: style.bodyFontSize * 0.35,
  );

  List<pw.InlineSpan> _spans(List<PdfSpan> spans, {double? size}) => [
    for (final span in spans) _span(span, size ?? style.bodyFontSize),
  ];

  pw.InlineSpan _span(PdfSpan span, double size) {
    final href = span.href;
    return pw.TextSpan(
      text: span.text,
      baseline: span.superscript ? size * 0.34 : 0,
      annotation: href == null || href.isEmpty
          ? null
          : pw.AnnotationUrl(href.trim()),
      style: pw.TextStyle(
        font: span.code ? fonts.mono : null,
        fontSize: span.code
            ? style.monoSize
            : (span.superscript ? size * 0.7 : size),
        fontWeight: span.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: span.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        decoration: _decorationFor(span),
        color: href == null || href.isEmpty ? null : style.accentColor,
      ),
    );
  }

  pw.TextDecoration? _decorationFor(PdfSpan span) {
    final hasLink = span.href != null && span.href!.isNotEmpty;
    if (span.strikeThrough && hasLink) {
      return pw.TextDecoration.combine([
        pw.TextDecoration.lineThrough,
        pw.TextDecoration.underline,
      ]);
    }
    if (span.strikeThrough) return pw.TextDecoration.lineThrough;
    if (hasLink) return pw.TextDecoration.underline;
    return null;
  }
}
