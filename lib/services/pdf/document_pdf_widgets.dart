// De tussenvorm uit `document_pdf_blocks.dart`, getekend als PDF-widgets.
//
// Bewust de dunne laag van de twee: alle beslissingen zijn al genomen — hier
// staat alleen nog hoe een kop, een tabel of een citaat eruitziet. Dat is de
// afspraak die de PDF-export toetsbaar houdt; zie de kop van
// `document_pdf_blocks.dart`.
//
// **Eén regel beheerst dit hele bestand: wikkel niets in wat niet breken kan.**
// `MultiPage` laat maar een handvol widgets over een bladovergang heen lopen
// (`Flex`, `Table`, `Wrap`, `Column`, en een `RichText` die op `span` staat).
// Wie zo'n widget in een `Container` zet om er marge of een achtergrond aan te
// geven, neemt hem dat vermogen af — en dan is een alinea die hoger is dan een
// bladzijde geen lelijke opmaak maar een harde fout die de hele export stukslaat.
// Daarom komt de witruimte hier uit losse tussenstukken in plaats van uit marges,
// en dragen een codeblok en een citaat hun achtergrond per regel in plaats van
// als één kader eromheen.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../models/settings.dart' show TableBorderStyle;
import '../../utils/log.dart';
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';
import 'document_pdf_inline_math.dart';
import 'document_pdf_orphan_safe_table.dart';
import 'document_pdf_style.dart';
import 'document_pdf_table_widths.dart';
import 'document_pdf_timeline.dart';

part 'parts/document_pdf_tables.dart';

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
    required this.verbatimLabel,
    required this.maxImageWidth,
    required this.maxImageHeight,
    this.images = const {},
    this.graphics = const {},
    this.headingPages = const {},
    this.onHeadingLaidOut,
  });

  final DocumentPdfStyle style;
  final DocumentPdfFonts fonts;

  /// Alle koppen in leesvolgorde, voor de inhoudsopgave en de ankers.
  final List<PdfHeadingEntry> headings;

  /// De aanduiding boven een blok dat letterlijk wordt weergegeven — ook een
  /// vertaalde tekst van de aanroeper.
  final String Function(PdfVerbatimKind kind) verbatimLabel;

  /// Hoe breed een afbeelding of tekening hoogstens mag worden: de bladspiegel.
  ///
  /// Uitdrukkelijk meegeven en niet aan de opmaak overlaten. Een SVG die zijn
  /// breedte als `100%` opgeeft — wat onze eigen grafiekgenerator doet, want in
  /// HTML betekent dat "vul de kolom" — leest `package:pdf` als honderd punten,
  /// en dan staat er een grafiek van drie centimeter op het blad. Een
  /// meegegeven breedte overstemt die waarde.
  final double maxImageWidth;

  /// Hoe hoog een afbeelding hoogstens mag worden.
  ///
  /// Een afbeelding kan niet over een bladovergang heen; is ze hoger dan de
  /// bladspiegel, dan kan `MultiPage` haar nergens kwijt en breekt de export af.
  /// De renderer rekent deze grens uit het werkelijke bladformaat — het is dus
  /// geen schatting maar de maat zelf.
  final double maxImageHeight;

  /// De bytes per afbeeldingsbron. Een PDF verwijst niet naar bestanden buiten
  /// zichzelf: wat er niet in zit, staat er niet in.
  final Map<String, Uint8List> images;

  /// De getekende vorm per formule-, mermaid- of grafiekblok, op de bron
  /// gesleuteld. Wat hier niet in staat valt terug op zijn bron in een kader —
  /// zie [_verbatim].
  final Map<String, PdfRenderedGraphic> graphics;

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
      if (block is PdfHeadingBlock && widgets.isNotEmpty) {
        widgets.add(pw.SizedBox(height: style.headingSpaceBefore(block.level)));
      }
      final next = index + 1 < blocks.length ? blocks[index + 1] : null;
      if (block is PdfHeadingBlock && next != null) {
        // Bij een lijst reist alleen het eerste punt mee. Een hele lijst binden
        // is óók een kop die niet alleen achterblijft, maar dan schuift er een
        // half blad wit voor in de plaats; één punt is genoeg om te laten zien
        // dat de lijst hier begint.
        final split = next is PdfListBlock ? _splitFirstItem(next) : null;
        final bound = split?.first ?? next;
        if (_bindsToHeading(bound)) {
          widgets.add(_headingBoundToNext(block, bound, tight: tight));
          index++;
          final rest = split?.rest;
          if (rest != null) {
            widgets.add(_widget(rest, tight: tight));
          }
          final spacingAfterPair = _spaceAfter(next, tight: tight);
          if (spacingAfterPair > 0) {
            widgets.add(pw.SizedBox(height: spacingAfterPair));
          }
          continue;
        }
        // De alinea is te lang om als geheel te binden, maar de kop mag toch
        // niet als wees onderaan staan. Splits de alinea op woordgrens: het
        // eerste deel reist met de kop mee, de rest volgt los (#1758).
        if (bound is PdfParagraphBlock) {
          final pair = splitParagraphAtWordBoundary(bound, _headingGuardChars);
          if (pair != null) {
            widgets.add(_headingBoundToNext(block, pair.first, tight: tight));
            widgets.add(_widget(pair.rest, tight: true));
            index++;
            final rest = split?.rest;
            if (rest != null) widgets.add(_widget(rest, tight: tight));
            final sp = _spaceAfter(next, tight: tight);
            if (sp > 0) widgets.add(pw.SizedBox(height: sp));
            continue;
          }
        }
      }
      // Alleen een widget die rechtstreeks in de lijst van `MultiPage` staat
      // mag over een bladovergang heen breken; een `Column` plaatst zijn
      // kinderen heel. De terugvalvorm van een te hoge tabel gaat daarom plat
      // de stroom in en niet als één blok (#1798).
      if (block is PdfTableBlock && _tableNeedsBlocks(block)) {
        widgets.addAll(_tableAsBlocks(block));
      } else {
        widgets.add(_widget(block, tight: tight));
      }
      final spacing = _spaceAfter(block, tight: tight);
      if (spacing > 0) widgets.add(pw.SizedBox(height: spacing));
    }
    return widgets;
  }

  /// De witruimte ná een blok. Komt als los tussenstuk in de stroom en niet als
  /// marge om het blok heen — zie de kop van dit bestand.
  double _spaceAfter(PdfBlock block, {required bool tight}) => switch (block) {
    PdfHeadingBlock() => style.headingSpaceAfter,
    PdfParagraphBlock() =>
      tight ? style.bodyFontSize * 0.15 : style.blockSpacing,
    PdfPageBreakBlock() => 0,
    _ => style.blockSpacing,
  };

  /// Een kop plus het blok erachter, als één geheel dat niet mag breken.
  pw.Widget _headingBoundToNext(
    PdfHeadingBlock heading,
    PdfBlock next, {
    required bool tight,
  }) => pw.Inseparable(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        pw.SizedBox(height: style.headingSpaceAfter),
        _widget(next, tight: tight),
      ],
    ),
  );

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
  /// daarvan.
  ///
  /// Op een klein vel (A6 en kleiner) is zelfs dat nog te veel; daar bindt deze
  /// laag helemaal niet, want een verweesde kop is een schoonheidsfout en een
  /// gebroken export niet.
  bool _bindsToHeading(PdfBlock block) {
    if (maxImageHeight < style.bodyFontSize * 20) return false;
    return switch (block) {
      PdfParagraphBlock(:final spans) =>
        spanTextLength(spans) <= keepTogetherChars,
      PdfCodeBlock(:final code) => code.length <= keepTogetherChars,
      PdfVerbatimBlock(:final source) => source.length <= keepTogetherChars,
      PdfListBlock(:final items) => _listTextLength(items) <= keepTogetherChars,
      _ => false,
    };
  }

  /// Splitst het eerste punt van een lijst af, zodat alleen dát met de kop mee
  /// hoeft te verhuizen. Geeft `null` terug bij een lijst van één punt — dan
  /// valt er niets te splitsen.
  static ({PdfListBlock first, PdfListBlock? rest})? _splitFirstItem(
    PdfListBlock list,
  ) {
    if (list.items.isEmpty) return null;
    final first = PdfListBlock(
      [list.items.first],
      ordered: list.ordered,
      startNumber: list.startNumber,
    );
    if (list.items.length == 1) return (first: first, rest: null);
    return (
      first: first,
      rest: PdfListBlock(
        list.items.sublist(1),
        ordered: list.ordered,
        // Doortellen vanaf waar het eerste punt ophield; anders begint de rest
        // van een genummerde lijst weer bij één.
        startNumber: list.startNumber + 1,
      ),
    );
  }

  /// De grens waarboven een blok niet meer als geheel aan zijn kop wordt
  /// gebonden. Ruwweg vijftien regels op A4 — ruim genoeg voor bijna elke
  /// alinea in een notitie of rapport. Boven deze grens wordt een alinea
  /// op woordgrens gesplitst: het eerste deel reist met de kop mee in een
  /// [pw.Inseparable], de rest volgt los. Zo staat een kop nooit als wees
  /// onderaan een bladzijde (#1758).
  ///
  /// Groter binden mag van `MultiPage` best, maar dan schuift er een gat van
  /// diezelfde hoogte voor de kop in de plaats — en een half leeg blad is
  /// zichtbaarder dan een verweesde kop.
  static const keepTogetherChars = 1200;

  /// Hoeveel tekens van een lange alinea meereizen met de kop in de
  /// [pw.Inseparable] — ruwweg drie regels, genoeg om de kop nooit alleen
  /// te laten staan.
  static const _headingGuardChars = 200;

  static int spanTextLength(List<PdfSpan> spans) =>
      spans.fold<int>(0, (sum, span) => sum + span.text.length);

  static int _listTextLength(List<PdfListItem> items) {
    var total = 0;
    for (final item in items) {
      for (final block in item.blocks) {
        if (block is PdfParagraphBlock) total += spanTextLength(block.spans);
      }
    }
    return total;
  }

  pw.Widget _widget(PdfBlock block, {required bool tight}) => switch (block) {
    PdfHeadingBlock() => _heading(block),
    PdfParagraphBlock() => _paragraph(block),
    PdfTimelineBlock() => _timeline(block),
    PdfListBlock() => _list(block),
    PdfQuoteBlock() => _quote(block),
    PdfCodeBlock() => _code(block.code),
    PdfVerbatimBlock() => _verbatim(block),
    PdfTableBlock() => _table(block),
    PdfImageBlock() => _image(block),
    PdfPageBreakBlock() => pw.NewPage(),
    PdfTocBlock() => _toc(),
  };

  pw.Widget _heading(PdfHeadingBlock block) {
    final entry = _headingCursor < headings.length
        ? headings[_headingCursor]
        : PdfHeadingEntry(_headingCursor, block.level, block.outlineText);
    _headingCursor++;
    final size = style.headingSize(block.level);
    final text = pw.RichText(
      // Een kop die zelf langer is dan een blad hoort ook te kunnen breken; hij
      // zit in geen enkel kader, dus dat mag gewoon.
      overflow: pw.TextOverflow.span,
      text: pw.TextSpan(
        style: _baseStyle.copyWith(
          fontSize: size,
          fontWeight: pw.FontWeight.bold,
          lineSpacing: size * 0.2,
          // Zelfde verdeling als op het scherm: een hoofdstukkop draagt de
          // kopkleur, een subkop de subkopkleur. Zonder kopkleur in het profiel
          // vallen die terug op de tekstkleur en het accent, en dan blijft dit
          // wat het was.
          color: block.level == 1 ? style.headingColor : style.subheadingColor,
        ),
        children: _spans(block.spans, size: size),
      ),
    );
    return pw.Outline(
      name: entry.anchor,
      title: entry.title,
      level: (block.level - 1).clamp(0, 5),
      child: _recordPage(entry.index, text),
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

  pw.Widget _paragraph(PdfParagraphBlock block) => pw.RichText(
    textAlign: pw.TextAlign.left,
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(style: _baseStyle, children: _spans(block.spans)),
  );

  pw.Widget _timeline(PdfTimelineBlock block) => buildDocumentPdfTimeline(
    block,
    style: style,
    baseStyle: _baseStyle,
    text: (spans, textStyle, {align}) => pw.RichText(
      overflow: pw.TextOverflow.span,
      textAlign: align ?? pw.TextAlign.left,
      text: pw.TextSpan(
        style: textStyle,
        children: _spans(spans, size: textStyle.fontSize),
      ),
    ),
  );

  /// Een citaat: een vlak in een tint van het accent, met een streep langs de
  /// linkerkant. Dezelfde vorm als de documentweergave op het scherm.
  ///
  /// De streep en het vlak zitten per blok en niet om het citaat heen, zodat de
  /// kolom eromheen een gewone [pw.Column] blijft die wél over een bladovergang
  /// mag lopen. Dat is ook waarom het vlak geen ruimte boven en onder krijgt:
  /// die zou per blok terugkomen en het citaat aan de binnenkant uit elkaar
  /// trekken. De lucht eromheen komt van de tussenstukken in [build].
  pw.Widget _quote(PdfQuoteBlock block) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final child in build(block.blocks))
        pw.Container(
          padding: pw.EdgeInsets.only(
            left: style.quotePadding,
            right: style.quotePadding,
          ),
          decoration: pw.BoxDecoration(
            color: style.quoteBackground,
            border: pw.Border(
              left: pw.BorderSide(
                color: style.accentColor,
                width: style.quoteBarWidth,
              ),
            ),
          ),
          child: child,
        ),
    ],
  );

  // ── Lijsten ──────────────────────────────────────────────────────────────

  pw.Widget _list(PdfListBlock block) {
    final rows = <pw.Widget>[];
    final gutter = _listGutter(block);
    var number = block.startNumber;
    for (final item in block.items) {
      rows.add(
        _listItem(
          item,
          gutter: gutter,
          marker: block.ordered ? '$number.' : null,
        ),
      );
      rows.add(pw.SizedBox(height: style.bodyFontSize * 0.25));
      if (block.ordered) number++;
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// De breedte van de goot vóór een lijstpunt.
  ///
  /// Een vaste [DocumentPdfStyle.indent] volstond tot item negen. Vanaf "10."
  /// paste het nummer er niet meer in en brak `package:pdf` het middenin af —
  /// de `1` op de ene regel, de `0.` op de volgende (#1791). De goot groeit
  /// daarom mee met het breedste merkteken van déze lijst. Eén maat voor de
  /// hele lijst en niet per punt, zodat de tekst links uitgelijnd blijft in
  /// plaats van bij item tien een stukje op te schuiven.
  double _listGutter(PdfListBlock block) {
    if (!block.ordered) return style.indent;
    final size = style.bodyFontSize;
    final hoogste = block.startNumber + block.items.length - 1;
    // Een cijfer is in Helvetica ~0,56 em en de punt ~0,28 em; daarbij de
    // rechtermarge die `_marker` zelf aanhoudt. Ruim schatten mag: een goot
    // die een haartje te breed is verschuift de tekst, een die te smal is
    // hakt het nummer doormidden.
    final nodig = ('$hoogste'.length * 0.56 + 0.28 + 0.4) * size;
    return math.max(style.indent, nodig);
  }

  pw.Widget _listItem(
    PdfListItem item, {
    required double gutter,
    String? marker,
  }) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: gutter, child: _marker(item, marker)),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: build(item.blocks, tight: true),
        ),
      ),
    ],
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

  /// Een codeblok: donkere achtergrond, vaste letterafstand.
  ///
  /// Per regel een eigen vlak, niet één kader om het geheel. Zo blijft de kolom
  /// een [pw.Column] die over een bladovergang mag lopen — een codeblok van
  /// honderd regels is geen zeldzaamheid, en als één kader zou het de export
  /// afbreken in plaats van door te lopen op het volgende blad.
  pw.Widget _code(String code) {
    final lines = code.trimRight().split('\n');
    final padding = style.bodyFontSize * 0.6;
    final textStyle = pw.TextStyle(
      font: fonts.mono,
      fontFallback: fonts.fallback,
      fontSize: style.monoSize,
      color: style.codeText,
      lineSpacing: style.monoSize * 0.3,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < lines.length; index++)
          pw.Container(
            color: style.codeBackground,
            padding: pw.EdgeInsets.only(
              left: padding,
              right: padding,
              top: index == 0 ? padding : 0,
              bottom: index == lines.length - 1 ? padding : 0,
            ),
            child: pw.Text(lines[index], style: textStyle),
          ),
      ],
    );
  }

  /// Een formule, een mermaid-diagram of een grafiek.
  ///
  /// Is er een getekende vorm, dan komt die in het bestand — bij voorkeur als
  /// vector, zodat het beeld scherp blijft en de tekst erin tekst blijft. Is die
  /// er niet, dan volgt de bron in een kader met een aanduiding erboven: liever
  /// leesbaar dan een leeg vlak, want wie het diagram nodig heeft weet dan
  /// tenminste wát er hoort te staan.
  pw.Widget _verbatim(PdfVerbatimBlock block) {
    final drawn = _graphic(block);
    if (drawn != null) return drawn;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
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
  }

  /// De getekende vorm van [block], of `null` als die er niet is of niet blijkt
  /// te werken.
  ///
  /// De `try` is geen overdreven voorzichtigheid. `pw.SvgImage` ontleedt de SVG
  /// al in zijn constructor, en een diagram met een constructie die de ontleder
  /// niet kent zou de héle export met een uitzondering afbreken — één diagram dat
  /// tegenvalt mag nooit het document kosten. Wat hier struikelt valt terug op de
  /// bron, precies zoals een diagram dat helemaal niet gerenderd kon worden.
  ///
  /// Breder dan `on Exception`, en met reden: een ontleder die op iets
  /// onverwachts stuit werpt net zo goed een `Error` (een index buiten bereik,
  /// een toestand die niet kan). Voor de uitkomst maakt dat niets uit — het
  /// diagram is er niet — dus mag het onderscheid hier niet bepalen of de export
  /// wel of niet stukloopt.
  pw.Widget? _graphic(PdfVerbatimBlock block) {
    final graphic = graphics[block.source.trim()];
    if (graphic == null) return null;
    final image = graphic.image;
    if (image != null) {
      return pw.Center(
        child: pw.ConstrainedBox(
          constraints: pw.BoxConstraints(
            maxWidth: maxImageWidth,
            maxHeight: maxImageHeight,
          ),
          child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
        ),
      );
    }
    final svg = graphic.svg;
    if (svg == null) return null;
    // De tekst ín de tekening gaat langs de SVG-lezer van `package:pdf` en niet
    // langs het thema; zie [DocumentPdfFonts.svgFont] voor waarom die lezer op
    // Latin-1 vastloopt. Draagt de tekening zulke tekens en is er geen snede die
    // ze kan zetten, dan is de bron meer waard dan een export die halverwege
    // afbreekt — dat is dezelfde afweging als hierboven, alleen kan de `try`
    // hem niet maken: de worp komt pas bij `save()`.
    final typesetting = fonts.svgTypesetting(svg);
    if (!typesetting.settable) {
      logWarning(
        'DocumentPdf: tekening bevat tekens buiten Latin-1 en er is geen '
        'Unicode-snede; de bron wordt getoond',
      );
      return null;
    }
    final svgFont = typesetting.font;
    try {
      // Nooit breder dan de bladspiegel, en nooit groter opgeblazen dan de
      // tekening zelf bedoelt. Zonder dat tweede wordt een driehoekje van drie
      // vakjes een poster van twintig centimeter, en dat is precies wat de
      // eerste echte render liet zien.
      final natural = graphic.naturalWidth;
      final width = natural == null || natural > maxImageWidth
          ? maxImageWidth
          : natural;
      final naturalHeight = graphic.naturalHeight;
      return pw.Center(
        child: pw.SvgImage(
          svg: svg,
          width: width,
          height: naturalHeight == null || naturalHeight > maxImageHeight
              ? maxImageHeight
              : naturalHeight,
          fit: pw.BoxFit.contain,
          customFontLookup: svgFont == null ? null : (_, _, _) => svgFont,
        ),
      );
    } catch (error) {
      logWarning('DocumentPdf: SVG kon niet geplaatst worden', error);
      return null;
    }
  }

  // ── Afbeeldingen ─────────────────────────────────────────────────────────

  pw.Widget _image(PdfImageBlock block) {
    final bytes = images[block.source];
    if (bytes == null) {
      // Onvindbaar of onleesbaar: zeg dát, met de beschrijving die de auteur
      // gaf. Een leeg gat laat de lezer denken dat er niets hoorde te staan.
      return pw.Text(
        block.alt.trim().isEmpty ? block.source : block.alt,
        style: _baseStyle.copyWith(
          fontStyle: pw.FontStyle.italic,
          color: style.bandTextColor,
        ),
      );
    }
    return pw.Center(
      child: pw.ConstrainedBox(
        constraints: pw.BoxConstraints(
          maxWidth: maxImageWidth,
          maxHeight: maxImageHeight,
        ),
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
      ),
    );
  }

  // ── Inhoudsopgave ────────────────────────────────────────────────────────

  pw.Widget _toc() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [for (final entry in headings) _tocEntry(entry)],
  );

  /// Eén regel van de inhoudsopgave: de kop links, het bladzijdenummer rechts.
  ///
  /// **Waarom geen stippellijn ertussen.** Die vraagt om een meerekkend vak
  /// tussen titel en nummer, en de flex-verdeling van `package:pdf` deelt de
  /// vrije ruimte dan tussen de titel én dat vak — waarna de regel korter
  /// uitvalt dan de bladspiegel en de nummers als een rafelrand onder elkaar
  /// komen te staan. Het alternatief (de titel niet-meerekkend maken) haalt die
  /// rafelrand weg maar zet er een ergere fout voor terug: een kop die langer is
  /// dan de regel loopt dan buiten het blad. Een meerekkende titel die netjes
  /// afbreekt en een nummer in een vaste kolom kan geen van beide.
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

  /// De opgemaakte tekst van de band boven- of onderaan de bladzijde.
  ///
  /// Loopt met opzet langs dezelfde spanrenderer als de lopende tekst: de band
  /// draagt Markdown, en die hoort in de PDF hetzelfde te doen als op het scherm
  /// en in de HTML-export. Eén regel hoog — een band die uitdijt duwt de
  /// tekstspiegel weg — en wat er niet in past valt er stil af.
  pw.Widget bandText(List<PdfSpan> spans, {required pw.TextStyle style}) =>
      pw.RichText(
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        text: pw.TextSpan(
          style: _baseStyle.merge(style),
          children: _spans(spans, size: style.fontSize ?? this.style.bandSize),
        ),
      );

  List<pw.InlineSpan> _spans(
    List<PdfSpan> spans, {
    double? size,
    double scale = 1,
  }) => [
    for (final span in spans)
      _span(span, (size ?? style.bodyFontSize) * scale, scale: scale),
  ];

  pw.InlineSpan _span(PdfSpan span, double size, {double scale = 1}) {
    if (span.math) {
      return buildDocumentPdfInlineMath(
        span,
        fontSize: size,
        maxWidth: maxImageWidth,
        graphics: graphics,
        fonts: fonts,
        fallback: (source) => _span(PdfSpan(source), size),
      );
    }
    final href = span.href;
    return pw.TextSpan(
      text: span.text,
      baseline: span.superscript ? size * 0.34 : 0,
      annotation: href == null || href.isEmpty
          ? null
          : pw.AnnotationUrl(href.trim()),
      style: pw.TextStyle(
        // Vaste-breedteletter in álle vier de sneden. Eén `font` is hier niet
        // genoeg: staat de code in een kop, dan erft de span het vette gewicht
        // van die kop, en `package:pdf` kiest de snede die bij het gewicht
        // hoort — dat is dan de schreefletter en niet de code.
        font: span.code ? fonts.mono : null,
        fontNormal: span.code ? fonts.mono : null,
        fontBold: span.code ? fonts.mono : null,
        fontItalic: span.code ? fonts.mono : null,
        fontBoldItalic: span.code ? fonts.mono : null,
        // Ook de vaste-breedteletter krimpt mee: juist daar staan de hashes
        // en IP-adressen die anders middenin afbreken (#1789).
        fontSize: span.code
            ? style.monoSize * scale
            : (span.superscript ? size * 0.7 : size),
        // `null` en niet `normal` wanneer de span er zelf niets van vindt. Een
        // kop staat al op vet, en een span die "gewoon" zégt overstemt dat —
        // waardoor élke kop in de export in de gewone snede stond. De opmaak
        // was er wel en werd één laag lager weer uitgezet.
        fontWeight: span.bold ? pw.FontWeight.bold : null,
        fontStyle: span.italic ? pw.FontStyle.italic : null,
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

int _tableColCount(PdfTableBlock block) =>
    block.rows.isEmpty ? 0 : block.rows.map((r) => r.length).fold(1, math.max);
