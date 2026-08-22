// De tussenvorm tussen Markdown en PDF.
//
// De LaTeX-export ([markdownToLatex]) schrijft rechtstreeks een string, en die
// string is zijn eigen toets: een test leest de uitvoer en ziet of er
// `\section{Titel}` staat. Een PDF heeft die luxe niet — de uitvoer is een
// binair bestand met glyph-indices, waar geen test iets in leest.
//
// Daarom gaat de PDF-export in twee stappen. Deze bestanden beschrijven de
// *beslissingen* (dit is een kop van niveau 2, dit is een tabel met een koprij,
// hier breekt de pagina), en pas de renderer giet ze in `package:pdf`-widgets.
// De beslissingen zijn daarmee even toetsbaar als de LaTeX-string, en de laag
// die het echt tekent blijft dun en saai.
//
// Alle inhoud die hier langskomt is al geprojecteerd (geredigeerd) door
// OciWacht — zie `writeDocumentExport` in `document_export_service.dart`, dat
// als `SurfaceKind.audience` geregistreerd staat.

import 'dart:typed_data';

/// Eén stuk tekst met zijn opmaak, binnen een alinea, kop of tabelcel.
///
/// Bewust plat en niet genest: Markdown staat `**vet _en cursief_**` toe, en een
/// boomvorm zou de renderer dwingen die te platten. Dat gebeurt hier al bij het
/// omzetten, zodat de renderer per stuk tekst precies één stijl krijgt.
class PdfSpan {
  const PdfSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strikeThrough = false,
    this.code = false,
    this.href,
    this.superscript = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strikeThrough;

  /// Inline code (`` `zo` ``): vaste letterafstand, geen opmaak eromheen.
  final bool code;

  /// Doelt de tekst ergens heen, dan draagt de PDF een klikbare verwijzing.
  final String? href;

  /// Hoger geplaatst en kleiner — het merkteken van een voetnoot.
  final bool superscript;

  PdfSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? strikeThrough,
    bool? code,
    String? href,
    bool? superscript,
  }) => PdfSpan(
    text ?? this.text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strikeThrough: strikeThrough ?? this.strikeThrough,
    code: code ?? this.code,
    href: href ?? this.href,
    superscript: superscript ?? this.superscript,
  );

  @override
  String toString() {
    final marks = [
      if (bold) 'b',
      if (italic) 'i',
      if (strikeThrough) 's',
      if (code) 'c',
      if (superscript) 'sup',
      if (href != null) 'href=$href',
    ].join(',');
    return marks.isEmpty ? 'PdfSpan($text)' : 'PdfSpan($text|$marks)';
  }

  @override
  bool operator ==(Object other) =>
      other is PdfSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strikeThrough == strikeThrough &&
      other.code == code &&
      other.href == href &&
      other.superscript == superscript;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, strikeThrough, code, href, superscript);
}

/// Een blok op de bladzijde. De volgorde van de lijst is de leesvolgorde.
sealed class PdfBlock {
  const PdfBlock();
}

/// Een kop, niveau 1 t/m 6. [level] 1 is een hoofdstuk.
///
/// [outlineText] is de platte tekst zonder opmaak; die gaat naar de
/// bladwijzerboom van de PDF, waar geen opmaak bestaat.
class PdfHeadingBlock extends PdfBlock {
  const PdfHeadingBlock(this.level, this.spans, this.outlineText);

  final int level;
  final List<PdfSpan> spans;
  final String outlineText;

  @override
  String toString() => 'PdfHeadingBlock(h$level, $outlineText)';
}

/// Een gewone alinea.
class PdfParagraphBlock extends PdfBlock {
  const PdfParagraphBlock(this.spans);

  final List<PdfSpan> spans;

  @override
  String toString() => 'PdfParagraphBlock(${spans.map((s) => s.text).join()})';
}

/// Eén punt in een lijst. Draagt zelf blokken, zodat een punt meer kan zijn dan
/// één regel: een alinea met daaronder een geneste lijst.
class PdfListItem {
  const PdfListItem(this.blocks, {this.checked});

  final List<PdfBlock> blocks;

  /// Gezet bij een GFM-takenlijst (`- [ ]` / `- [x]`); anders `null`.
  final bool? checked;
}

/// Een lijst, geordend (genummerd) of niet.
class PdfListBlock extends PdfBlock {
  const PdfListBlock(this.items, {required this.ordered, this.startNumber = 1});

  final List<PdfListItem> items;
  final bool ordered;

  /// Waar een genummerde lijst begint — `3. ` in de bron telt door vanaf drie.
  final int startNumber;

  @override
  String toString() =>
      'PdfListBlock(${ordered ? 'ol' : 'ul'}, ${items.length} punten)';
}

/// Een gemarkeerde documenttijdlijn, los van de tabel waaruit hij is afgeleid.
///
/// Een eigen blok voorkomt dat een export de visuele betekenis opnieuw moet
/// raden uit een lijst of tabel. De bron zelf blijft ongewijzigd Markdown.
class PdfTimelineBlock extends PdfBlock {
  const PdfTimelineBlock(this.headers, this.events);

  final List<String> headers;
  final List<PdfTimelineEvent> events;

  @override
  String toString() => 'PdfTimelineBlock(${events.length} gebeurtenissen)';
}

/// Eén rij uit een [PdfTimelineBlock], met de inline-opmaak per cel behouden.
class PdfTimelineEvent {
  const PdfTimelineEvent(this.marker, this.event, {this.metadata});

  final List<PdfSpan> marker;
  final List<PdfSpan> event;
  final List<PdfSpan>? metadata;
}

/// Een citaat (`>`), met alles wat erin staat.
class PdfQuoteBlock extends PdfBlock {
  const PdfQuoteBlock(this.blocks);

  final List<PdfBlock> blocks;

  @override
  String toString() => 'PdfQuoteBlock(${blocks.length} blokken)';
}

/// Een codeblok, letterlijk weer te geven.
class PdfCodeBlock extends PdfBlock {
  const PdfCodeBlock(this.code, {this.language});

  final String code;
  final String? language;

  @override
  String toString() => 'PdfCodeBlock(${language ?? 'geen taal'})';
}

/// Een tabel. De eerste rij is de koprij wanneer [hasHeader] geldt.
class PdfTableBlock extends PdfBlock {
  const PdfTableBlock(this.rows, {required this.hasHeader, this.alignments});

  /// Rijen → cellen → de opgemaakte stukken tekst in die cel.
  final List<List<List<PdfSpan>>> rows;
  final bool hasHeader;

  /// De uitlijning per kolom uit de scheidingsrij (`:---`, `:---:`, `---:`),
  /// of `null` wanneer de bron niets zei.
  final List<PdfColumnAlignment>? alignments;

  @override
  String toString() => 'PdfTableBlock(${rows.length} rijen)';
}

/// De uitlijning van een tabelkolom.
enum PdfColumnAlignment { left, center, right }

/// Een afbeelding. [source] is het pad of de URI zoals in de bron; de renderer
/// krijgt de bytes van de aanroeper — een PDF verwijst niet naar bestanden
/// buiten zichzelf, alles zit erin.
class PdfImageBlock extends PdfBlock {
  const PdfImageBlock(this.source, {this.alt = ''});

  final String source;
  final String alt;

  @override
  String toString() => 'PdfImageBlock($source)';
}

/// Een pagina-einde. In documentmodus is een `---` geen streep maar een nieuw
/// blad (DOCUMENT_MODE.md §13) — precies zoals de LaTeX-export er `\newpage`
/// van maakt.
class PdfPageBreakBlock extends PdfBlock {
  const PdfPageBreakBlock();

  @override
  String toString() => 'PdfPageBreakBlock()';
}

/// De plek waar de inhoudsopgave hoort (`<!-- toc -->`).
///
/// De renderer vult hem: koppen met hun bladzijdenummer, elk een klikbare
/// sprong. Dat kan pas ná de opmaak — vóór het pagineren weet niemand op welk
/// blad een kop landt.
class PdfTocBlock extends PdfBlock {
  const PdfTocBlock();

  @override
  String toString() => 'PdfTocBlock()';
}

/// Een blok dat OciDeck in een PDF niet zelf kan tekenen en daarom letterlijk
/// laat zien: de bron, in vaste letterafstand, met een aanduiding erboven.
///
/// Dit zijn wiskunde (`$$…$$`), Mermaid-diagrammen en grafiekblokken. De
/// HTML-export rendert die met een JavaScript-laag die in een PDF niet bestaat,
/// en de LaTeX-export laat Mermaid en grafieken om dezelfde reden als codeblok
/// staan. Liever de bron leesbaar dan een leeg vlak: wie het diagram nodig
/// heeft weet dan tenminste wát er hoort te staan.
class PdfVerbatimBlock extends PdfBlock {
  const PdfVerbatimBlock(this.source, {required this.kind});

  final String source;
  final PdfVerbatimKind kind;

  @override
  String toString() => 'PdfVerbatimBlock(${kind.name})';
}

/// Waarom een blok letterlijk wordt weergegeven. De renderer maakt er een
/// aanduiding bij; de tekst daarvan komt van de aanroeper, want deze laag kent
/// geen vertalingen.
enum PdfVerbatimKind { math, mermaid, chart }

/// Een blok dat OciDeck wél kon tekenen, klaar om in de PDF te zetten.
///
/// Twee vormen, en de keuze is niet willekeurig. Een **SVG** gaat als vector het
/// bestand in: scherp op elke zoomstand, klein, en de tekst erin blijft tekst —
/// wat er in een document dat zijn tekstlaag als belofte draagt nogal toe doet.
/// Een **afbeelding** is de terugval voor wat alleen als pixels bestaat.
///
/// Wat geen van beide vormen kan opleveren, valt terug op de bron
/// ([PdfVerbatimBlock]). Die terugval is geen nette bijkomstigheid maar de kern:
/// een diagram dat niet getekend kan worden mag de export nooit afbreken, en
/// mag al helemaal geen leeg vlak achterlaten.
class PdfRenderedGraphic {
  const PdfRenderedGraphic.svg(
    String this.svg, {
    this.naturalWidth,
    this.naturalHeight,
  }) : image = null;

  const PdfRenderedGraphic.image(
    Uint8List this.image, {
    this.naturalWidth,
    this.naturalHeight,
  }) : svg = null;

  /// De vectorvorm, als die er is.
  final String? svg;

  /// De beeldvorm, als die er is.
  final Uint8List? image;

  /// De maat die de tekening zelf bedoelt, in punten — of `null` als die niet
  /// af te leiden viel.
  ///
  /// Zonder deze maat is er maar één redelijke keuze: de tekening zo breed
  /// maken als de bladspiegel. Voor een grafiek klopt dat, want die is bedoeld
  /// om de kolom te vullen. Voor een driehoekje van een stroomdiagram niet, en
  /// voor een formule al helemaal niet — die hoort in de lopende tekst te passen
  /// en niet als poster over het blad te liggen.
  final double? naturalWidth;
  final double? naturalHeight;

  @override
  String toString() => svg != null
      ? 'PdfRenderedGraphic.svg(${svg!.length} tekens)'
      : 'PdfRenderedGraphic.image(${image!.length} bytes)';
}
