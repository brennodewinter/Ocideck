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

import '../../models/deck.dart' show TlpLevel, TlpLevelX;
import '../../models/page_size.dart';
import '../document_deck_bridge.dart';
import '../document_chrome_template.dart';
import '../export_bundle.dart';
import '../export_metadata.dart';
import '../marp_html_service.dart' show HtmlImageResolver;
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';
import 'document_pdf_renderer.dart';
import 'document_pdf_style.dart';
import 'markdown_to_pdf_blocks.dart';

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
  final logo = await _resolveLogo(theme.effectiveDocumentLogoPath, embedImage);

  final fields = {
    ...deck.documentFields,
    'title': deck.title,
    'subtitle': deck.description,
    'author': deck.author,
  };
  final bytes = await buildDocumentPdf(
    blocks,
    style: DocumentPdfStyle.fromTheme(theme),
    fonts: fonts,
    verbatimLabel: labels.labelFor,
    images: images,
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
