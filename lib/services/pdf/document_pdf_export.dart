// Van exportbundel naar PDF-bytes.
//
// De schakel tussen `writeDocumentExport` en de PDF-lagen eronder: leest de
// *geprojecteerde* (geredigeerde) body uit de bundel, haalt de afbeeldingen op,
// zet het stijlprofiel om en levert de bytes.
//
// Deze functie schrijft zelf niets weg. Dat is opzet: het wegschrijven blijft in
// `writeDocumentExport`, het ene oppervlak dat als `SurfaceKind.audience`
// geregistreerd staat in `tool/check_audience_boundary.dart`. Zo blijft er één
// plek waar documentinhoud de map van de gebruiker verlaat.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

import '../../models/chart.dart';
import '../../models/deck.dart' show TlpLevel, TlpLevelX;
import '../../models/page_size.dart';
import '../../models/settings.dart' show ThemeProfile;
import '../document_deck_bridge.dart';
import '../document_chrome_template.dart';
import '../export_bundle.dart';
import '../export_metadata.dart';
import '../marp_html_service.dart' show HtmlImageResolver, MarpHtmlService;
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';
import 'document_pdf_renderer.dart';
import 'document_pdf_svg.dart';
import 'document_pdf_style.dart';
import 'markdown_to_pdf_blocks.dart';

/// Zet een mermaid-bron om in SVG.
///
/// De renderer daarvoor draait op een verborgen WebView en woont dus in de
/// schil; deze laag vraagt er alleen om. Levert `null` wanneer het diagram niet
/// gerenderd kan worden — dan valt het blok terug op zijn bron.
typedef MermaidSvgResolver = Future<String?> Function(String source);

/// Zet een TeX-formule om in SVG. Zelfde afspraak als [MermaidSvgResolver].
typedef MathSvgResolver = Future<String?> Function(String tex);

/// De teksten die de PDF-lagen nodig hebben maar niet zelf kennen.
///
/// De omzetting en de renderer zijn zuiver tekst-in, bytes-uit en dragen geen
/// vertalingen — hetzelfde patroon als `endnotesTitle` bij de LaTeX-export.
class DocumentPdfLabels {
  const DocumentPdfLabels({
    required this.footnotesTitle,
    required this.mathLabel,
    required this.mermaidLabel,
    required this.chartLabel,
  });

  final String footnotesTitle;

  /// De aanduiding boven een blok dat de PDF niet kan tekenen en daarom
  /// letterlijk toont.
  final String mathLabel;
  final String mermaidLabel;
  final String chartLabel;

  String labelFor(PdfVerbatimKind kind) => switch (kind) {
    PdfVerbatimKind.math => mathLabel,
    PdfVerbatimKind.mermaid => mermaidLabel,
    PdfVerbatimKind.chart => chartLabel,
  };
}

/// Wat de export opleverde: de bytes, plus wat er niet in kon.
class DocumentPdfResult {
  const DocumentPdfResult(this.bytes, {this.unsupportedCharacters = const {}});

  final Uint8List bytes;

  /// De tekens waarvoor geen enkele beschikbare snede een vorm had.
  ///
  /// Leeg is de normale uitkomst. Staat er iets in, dan is de PDF geschreven
  /// maar mist hij die tekens — en dan hoort de gebruiker dat te horen in plaats
  /// van het zelf te ontdekken. Zie [DocumentPdfFonts.unsupportedRunes].
  final Set<int> unsupportedCharacters;

  bool get isComplete => unsupportedCharacters.isEmpty;
}

/// Bouwt de PDF voor het document in [bundle].
///
/// De inhoud komt uit `bundle.audience.deck` — de geprojecteerde body, nooit de
/// rauwe bron. [embedImage] is dezelfde resolver die de HTML-export gebruikt: hij
/// levert een `data:`-URI, waaruit hier de bytes komen die in het bestand
/// belanden.
Future<DocumentPdfResult> buildDocumentExportPdf(
  ExportBundle bundle, {
  required DocumentPdfLabels labels,
  ByteData? fallbackFont,
  HtmlImageResolver? embedImage,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  bool chapterPageBreak = false,
  bool cropMarks = false,
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  ExportDocumentMetadata? metadata,
}) async {
  final deck = bundle.audience.deck;
  final body = DocumentDeckBridge.deckToDocumentMarkdown(deck);
  final theme = deck.themeProfile;
  final blocks = markdownToPdfBlocks(
    body,
    chapterPageBreak: chapterPageBreak,
    footnotesTitle: labels.footnotesTitle,
  );

  final fonts = DocumentPdfFonts.forFamily(
    theme.fontFamily,
    fallbackFont: fallbackFont,
  );
  final images = await _resolveImages(blocks, embedImage);
  final style = DocumentPdfStyle.fromTheme(theme);
  final graphics = await _resolveGraphics(
    blocks,
    theme,
    style,
    renderMermaid: renderMermaid,
    renderMath: renderMath,
  );
  final logo = await _resolveLogo(theme.effectiveDocumentLogoPath, embedImage);

  final fields = {
    ...deck.documentFields,
    'title': deck.title,
    'subtitle': deck.description,
    'author': deck.author,
  };
  final bytes = await buildDocumentPdf(
    blocks,
    style: style,
    fonts: fonts,
    verbatimLabel: labels.labelFor,
    images: images,
    graphics: graphics,
    chrome: DocumentPdfChrome(
      headerText: resolveDocumentChromeTemplate(
        theme.documentHeaderText.trim(),
        fields,
      ),
      footerText: resolveDocumentChromeTemplate(
        theme.documentFooterText.trim(),
        fields,
      ),
      showPageNumbers: theme.documentShowPageNumbers,
      tlpLabel: deck.tlp == TlpLevel.none ? '' : deck.tlp.label,
      tlpColor: deck.tlp == TlpLevel.none
          ? null
          : PdfColor.fromInt(0xFF000000 | (deck.tlp.foreground & 0xFFFFFF)),
      logo: logo,
      logoAtTop: theme.documentLogoPosition.startsWith('top'),
      logoAtRight: theme.documentLogoPosition.endsWith('right'),
      logoHeight: (theme.documentLogoSize ?? 32).toDouble() * 0.5,
    ),
    pageSize: pageSize,
    pageMargins: pageMargins,
    cropMarks: cropMarks,
    metadata: metadata,
  );

  return DocumentPdfResult(
    bytes,
    unsupportedCharacters: fonts.unsupportedRunes(_textOf(blocks)),
  );
}

/// Haalt de bytes op van elke afbeelding die in de blokken voorkomt.
///
/// Een bron die niets oplevert wordt overgeslagen; de renderer zet er dan de
/// beschrijving neer in plaats van een gat (`_image` in
/// `document_pdf_widgets.dart`).
Future<Map<String, Uint8List>> _resolveImages(
  List<PdfBlock> blocks,
  HtmlImageResolver? embedImage,
) async {
  if (embedImage == null) return const {};
  final sources = <String>{};
  void walk(List<PdfBlock> list) {
    for (final block in list) {
      switch (block) {
        case PdfImageBlock(:final source):
          if (source.trim().isNotEmpty) sources.add(source);
        case PdfQuoteBlock(:final blocks):
          walk(blocks);
        case PdfListBlock(:final items):
          for (final item in items) {
            walk(item.blocks);
          }
        default:
          break;
      }
    }
  }

  walk(blocks);
  final images = <String, Uint8List>{};
  for (final source in sources) {
    final bytes = await _bytesOf(source, embedImage);
    if (bytes != null) images[source] = bytes;
  }
  return images;
}

/// Tekent wat er te tekenen valt: grafieken, mermaid-diagrammen en formules.
///
/// **Grafieken gaan zuiver in Dart.** `MarpHtmlService.chartSpecSvg` is dezelfde
/// generator die de HTML-export en de documentweergave gebruiken, dus er komt
/// geen vierde renderwereld bij — de PDF toont wat het scherm toont, van
/// dezelfde regels afgeleid.
///
/// **Mermaid en wiskunde komen van de aanroeper**, want hun renderers draaien op
/// een verborgen WebView en dat is schilwerk. Levert zo'n renderer niets op, dan
/// blijft het blok gewoon weg uit de kaart en valt het terug op zijn bron.
///
/// Op de *bron* gesleuteld, niet op volgorde: twee keer hetzelfde diagram in één
/// document wordt één keer gerenderd.
Future<Map<String, PdfRenderedGraphic>> _resolveGraphics(
  List<PdfBlock> blocks,
  ThemeProfile theme,
  DocumentPdfStyle style, {
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
}) async {
  final wanted = <String, PdfVerbatimKind>{};
  void walk(List<PdfBlock> list) {
    for (final block in list) {
      switch (block) {
        case PdfVerbatimBlock(:final source, :final kind):
          final key = source.trim();
          if (key.isNotEmpty) wanted[key] = kind;
        case PdfQuoteBlock(:final blocks):
          walk(blocks);
        case PdfListBlock(:final items):
          for (final item in items) {
            walk(item.blocks);
          }
        default:
          break;
      }
    }
  }

  walk(blocks);
  final graphics = <String, PdfRenderedGraphic>{};
  for (final entry in wanted.entries) {
    final svg = switch (entry.value) {
      PdfVerbatimKind.chart => _chartSvg(entry.key, theme),
      PdfVerbatimKind.mermaid => await renderMermaid?.call(entry.key),
      PdfVerbatimKind.math => await renderMath?.call(entry.key),
    };
    if (svg == null || svg.trim().isEmpty) continue;
    // Klaarmaken vóór het de renderer in gaat: de maat eraf en zelf uitgerekend,
    // en `currentColor` vervangen. Zie `document_pdf_svg.dart` voor waarom een
    // SVG die in een browser klopt hier anders scheef of onzichtbaar wordt.
    final prepared = prepareSvgForPdf(
      svg,
      // `toHex()` levert `#RRGGBBAA`; de doorzichtigheid hoort niet in een
      // SVG-kleur thuis en maakte er `#22222ff` van — een kleur die de lezer
      // niet kent, en een onbekende kleur tekent niets.
      inkHex: style.textColor.toHex().substring(0, 7),
      fontSizePt: style.bodyFontSize,
    );
    graphics[entry.key] = PdfRenderedGraphic.svg(
      prepared.svg,
      naturalWidth: prepared.size?.width,
      naturalHeight: prepared.size?.height,
    );
  }
  return graphics;
}

/// De SVG van één grafiekblok, of `null` als er niets te tekenen valt.
///
/// De grond is het papier en niet de kaartkleur van het scherm: de generator
/// kiest zijn inkt zo dat titel en legenda leesbaar blijven op de ondergrond die
/// je hem noemt, en in een PDF is dat wit.
String? _chartSvg(String source, ThemeProfile theme) {
  final spec = ChartSpec.parse(source);
  // Zonder inline cijfers geeft de generator een lege SVG terug — een leeg vlak
  // op papier, waar de bron tenminste nog leesbaar is. Dat gebeurt wanneer de
  // gegevens in een los `data/*.json` staan dat niet mee kon komen.
  if (!spec.hasInlineData) return null;
  return MarpHtmlService.chartSpecSvg(spec, theme, background: '#FFFFFF');
}

Future<Uint8List?> _resolveLogo(
  String? logoPath,
  HtmlImageResolver? embedImage,
) async {
  final path = logoPath?.trim();
  if (path == null || path.isEmpty || embedImage == null) return null;
  return _bytesOf(path, embedImage);
}

/// De bytes achter één bron, via de `data:`-URI die de resolver teruggeeft.
Future<Uint8List?> _bytesOf(String source, HtmlImageResolver embedImage) async {
  final uri = await embedImage(source);
  if (uri == null) return null;
  final comma = uri.indexOf(',');
  if (comma < 0 || !uri.startsWith('data:')) return null;
  // Alleen base64 — een `data:`-URI met platte tekst draagt geen afbeelding die
  // een PDF kan plaatsen (SVG hoort daar ook bij: `package:pdf` tekent geen SVG
  // zonder de losse `printing`-laag, die deze export niet heeft).
  if (!uri.substring(0, comma).contains(';base64')) return null;
  try {
    return base64Decode(uri.substring(comma + 1));
  } on FormatException {
    return null;
  }
}

/// Alle tekst die in het bestand terechtkomt, voor de dekkingscontrole van de
/// lettersneden.
String _textOf(List<PdfBlock> blocks) {
  final buffer = StringBuffer();
  void walk(List<PdfBlock> list) {
    for (final block in list) {
      switch (block) {
        case PdfHeadingBlock(:final spans):
        case PdfParagraphBlock(:final spans):
          for (final span in spans) {
            buffer.write(span.text);
          }
        case PdfCodeBlock(:final code):
          buffer.write(code);
        case PdfVerbatimBlock(:final source):
          buffer.write(source);
        case PdfTableBlock(:final rows):
          for (final row in rows) {
            for (final cell in row) {
              for (final span in cell) {
                buffer.write(span.text);
              }
            }
          }
        case PdfQuoteBlock(:final blocks):
          walk(blocks);
        case PdfListBlock(:final items):
          for (final item in items) {
            walk(item.blocks);
          }
        default:
          break;
      }
    }
  }

  walk(blocks);
  return buffer.toString();
}
