// Het document als PDF-bestand: bladzijden, banden, snijtekens, bladwijzers.
//
// Dit is de laag die pagineert. Alles wat er binnenkomt is al beslist
// (`document_pdf_blocks.dart`) en al getekend (`document_pdf_widgets.dart`);
// hier krijgt het een vel, een marge en een volgorde.
//
// **Waarom twee opmaakrondes.** Een inhoudsopgave staat vooraan en noemt
// bladzijden die pas verderop worden bepaald — hetzelfde probleem waarvoor
// LaTeX zijn `.aux`-bestand heeft en waarom je een LaTeX-document twee keer
// compileert. De eerste ronde maakt het document op en onthoudt op welk blad
// elke kop landde; de tweede zet die nummers in de inhoudsopgave. Dat de opmaak
// tussen de rondes niet verschuift, is geen hoop maar bouw: de kolom met
// nummers heeft in beide rondes dezelfde breedte (zie `_tocEntry`).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/page_size.dart';
import '../export_metadata.dart';
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';
import 'document_pdf_style.dart';
import 'document_pdf_widgets.dart';

/// De band boven en onder elke bladzijde: vrije tekst, bladzijdenummer, de
/// classificatie-aanduiding en het logo.
///
/// De teksten komen al ingevuld binnen — tokens zijn vervangen en, belangrijker,
/// ze zijn al door de privacyprojectie gegaan (`privacy_projection.dart` doet
/// dat voor de kop- en voettekst van het stijlprofiel). Deze laag zet ze neer,
/// ze bedenkt er niets bij.
class DocumentPdfChrome {
  const DocumentPdfChrome({
    this.headerText = '',
    this.footerText = '',
    this.showPageNumbers = false,
    this.tlpLabel = '',
    this.tlpColor,
    this.logo,
    this.logoAtTop = false,
    this.logoAtRight = true,
    this.logoHeight = 24,
  });

  final String headerText;
  final String footerText;
  final bool showPageNumbers;

  /// De classificatie-aanduiding (TLP), of leeg wanneer het document er geen
  /// draagt. Staat rechtsonder, net als in de HTML-export.
  final String tlpLabel;
  final PdfColor? tlpColor;

  final Uint8List? logo;
  final bool logoAtTop;
  final bool logoAtRight;
  final double logoHeight;

  bool get hasHeader =>
      headerText.trim().isNotEmpty || (logo != null && logoAtTop);

  bool get hasFooter =>
      footerText.trim().isNotEmpty ||
      showPageNumbers ||
      tlpLabel.trim().isNotEmpty ||
      (logo != null && !logoAtTop);
}

/// Bouwt het PDF-bestand voor een document en geeft de bytes terug.
///
/// [verbatimLabel] en [tocTitle] komen van de aanroeper omdat deze laag geen
/// vertalingen kent — hetzelfde patroon als de LaTeX-export met zijn
/// `endnotesTitle`.
Future<Uint8List> buildDocumentPdf(
  List<PdfBlock> blocks, {
  required DocumentPdfStyle style,
  required DocumentPdfFonts fonts,
  required String Function(PdfVerbatimKind kind) verbatimLabel,
  Map<String, Uint8List> images = const {},
  DocumentPdfChrome chrome = const DocumentPdfChrome(),
  PageSizeSpec? pageSize,
  PageMargins? pageMargins,
  bool cropMarks = false,
  ExportDocumentMetadata? metadata,
}) async {
  final size = pageSize ?? PageSizeSpec.a4;
  final margins = pageMargins ?? const PageMargins();
  final headings = headingEntriesOf(blocks);
  final needsSecondPass = blocks.any((b) => b is PdfTocBlock);

  final headingPages = <int, int>{};
  if (needsSecondPass) {
    // Eerste ronde: alleen om te weten te komen waar de koppen landen. De
    // bytes gooien we weg — het gaat om wat het opmaken heeft uitgerekend.
    await _render(
      blocks,
      style: style,
      fonts: fonts,
      headings: headings,
      verbatimLabel: verbatimLabel,
      images: images,
      chrome: chrome,
      size: size,
      margins: margins,
      cropMarks: cropMarks,
      metadata: metadata,
      onHeadingLaidOut: (index, page) => headingPages[index] = page,
    );
  }

  return _render(
    blocks,
    style: style,
    fonts: fonts,
    headings: headings,
    verbatimLabel: verbatimLabel,
    images: images,
    chrome: chrome,
    size: size,
    margins: margins,
    cropMarks: cropMarks,
    metadata: metadata,
    headingPages: headingPages,
  );
}

Future<Uint8List> _render(
  List<PdfBlock> blocks, {
  required DocumentPdfStyle style,
  required DocumentPdfFonts fonts,
  required List<PdfHeadingEntry> headings,
  required String Function(PdfVerbatimKind kind) verbatimLabel,
  required Map<String, Uint8List> images,
  required DocumentPdfChrome chrome,
  required PageSizeSpec size,
  required PageMargins margins,
  required bool cropMarks,
  ExportDocumentMetadata? metadata,
  Map<int, int> headingPages = const {},
  void Function(int index, int page)? onHeadingLaidOut,
}) async {
  final document = pw.Document(
    title: metadata?.title,
    author: metadata?.documentAuthor,
    subject: metadata?.description,
    keywords: metadata?.keywords,
    creator: metadata?.creator,
    producer: metadata?.producer,
    // De bladwijzerboom staat open zodra de lezer het bestand opent: in een
    // document van enige lengte is dat de snelste weg naar het hoofdstuk dat je
    // zoekt, en een dichtgeklapt zijpaneel vindt niemand uit zichzelf.
    pageMode: headings.isEmpty ? PdfPageMode.none : PdfPageMode.outlines,
  );

  final pageTheme = _pageTheme(
    style: style,
    fonts: fonts,
    size: size,
    margins: margins,
    cropMarks: cropMarks,
  );
  final builder = DocumentPdfWidgets(
    style: style,
    fonts: fonts,
    headings: headings,
    verbatimLabel: verbatimLabel,
    // Ruim onder de bladspiegel: de banden boven en onder eten er nog van, en
    // een afbeelding die net niet past kan `MultiPage` nergens kwijt.
    maxImageHeight: pageTheme.pageFormat.availableHeight * 0.8,
    images: images,
    headingPages: headingPages,
    onHeadingLaidOut: onHeadingLaidOut,
  );

  document.addPage(
    pw.MultiPage(
      pageTheme: pageTheme,
      header: chrome.hasHeader
          ? (context) => _band(context, chrome, style, top: true)
          : null,
      footer: chrome.hasFooter
          ? (context) => _band(context, chrome, style, top: false)
          : null,
      build: (context) => builder.build(blocks),
    ),
  );

  return Uint8List.fromList(await document.save());
}

/// Het vel: het formaat plus de afloop, met de tekstspiegel op zijn plek.
///
/// Bij afloop wordt het blad rondom [PageMargins.bleedMm] groter dan het
/// gekozen formaat, en schuift de marge evenveel op — precies zoals
/// [PageMargins.latexGeometry] het voor LaTeX en `cssMargin` het voor de
/// HTML-afdruk doet. Eén afspraak, drie uitvoerpaden.
pw.PageTheme _pageTheme({
  required DocumentPdfStyle style,
  required DocumentPdfFonts fonts,
  required PageSizeSpec size,
  required PageMargins margins,
  required bool cropMarks,
}) {
  final (trimWidthMm, trimHeightMm) = size.dimensions;
  final bleed = margins.bleedMm;
  final format = PdfPageFormat(
    mmToPt(trimWidthMm + bleed * 2),
    mmToPt(trimHeightMm + bleed * 2),
    marginTop: mmToPt(margins.topMm + bleed),
    marginBottom: mmToPt(margins.bottomMm + bleed),
    marginLeft: mmToPt(margins.leftMm + bleed),
    marginRight: mmToPt(margins.rightMm + bleed),
  );
  final drawCropMarks = cropMarks && margins.hasBleed;
  return pw.PageTheme(
    pageFormat: format,
    theme: fonts.themeData(
      fontSize: style.bodyFontSize,
      color: style.textColor,
    ),
    buildBackground: drawCropMarks
        ? (context) => _cropMarks(format, mmToPt(bleed))
        : null,
  );
}

/// De snijtekens rond het uiteindelijke formaat.
///
/// Alleen zinvol mét afloop: zonder afloop valt de snijlijn samen met de rand
/// van het blad en zouden de tekens ín het drukwerk staan. Dezelfde voorwaarde
/// als in de LaTeX-preamble, en de HTML-afdruk belooft ze helemaal niet — geen
/// browser kent `marks` uit CSS Paged Media.
pw.Widget _cropMarks(PdfPageFormat format, double bleed) {
  const markLength = 8.0;
  const gap = 3.0;
  const thickness = 0.3;
  final right = format.width - bleed;
  final bottom = format.height - bleed;
  return pw.FullPage(
    ignoreMargins: true,
    child: pw.CustomPaint(
      size: PdfPoint(format.width, format.height),
      painter: (canvas, pdfSize) {
        canvas
          ..setStrokeColor(PdfColors.black)
          ..setLineWidth(thickness);
        // De PDF telt van onderaf; de vier hoeken krijgen elk een horizontaal
        // en een verticaal streepje, met een tussenruimte zodat ze het
        // drukwerk zelf niet raken.
        for (final x in [bleed, right]) {
          for (final y in [bleed, bottom]) {
            final flipped = format.height - y;
            final inwardX = x == bleed ? -1.0 : 1.0;
            final inwardY = flipped < format.height / 2 ? 1.0 : -1.0;
            canvas
              ..drawLine(
                x + inwardX * gap,
                flipped,
                x + inwardX * (gap + markLength),
                flipped,
              )
              ..drawLine(
                x,
                flipped + inwardY * gap,
                x,
                flipped + inwardY * (gap + markLength),
              );
          }
        }
        canvas.strokePath();
      },
    ),
  );
}

/// De band boven of onder de bladzijde.
pw.Widget _band(
  pw.Context context,
  DocumentPdfChrome chrome,
  DocumentPdfStyle style, {
  required bool top,
}) {
  final text = top ? chrome.headerText.trim() : chrome.footerText.trim();
  final logo = chrome.logo;
  final showLogo = logo != null && chrome.logoAtTop == top;
  final textStyle = pw.TextStyle(
    fontSize: style.bandSize,
    color: style.bandTextColor,
  );
  final children = <pw.Widget>[
    if (showLogo && !chrome.logoAtRight)
      _logo(logo, chrome.logoHeight)
    else
      pw.SizedBox(),
    pw.Expanded(child: pw.Text(text, style: textStyle)),
    if (!top && chrome.showPageNumbers)
      pw.Text('${context.pageNumber}', style: textStyle),
    if (!top && chrome.tlpLabel.trim().isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8),
        child: pw.Text(
          chrome.tlpLabel,
          style: textStyle.copyWith(
            color: chrome.tlpColor ?? style.bandTextColor,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    if (showLogo && chrome.logoAtRight)
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8),
        child: _logo(logo, chrome.logoHeight),
      ),
  ];
  return pw.Container(
    margin: pw.EdgeInsets.only(
      bottom: top ? style.bodyFontSize * 0.8 : 0,
      top: top ? 0 : style.bodyFontSize * 0.8,
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    decoration: pw.BoxDecoration(
      color: style.bandBackgroundColor,
      border: pw.Border(
        top: top
            ? pw.BorderSide.none
            : pw.BorderSide(color: style.bandTextColor, width: 0.3),
        bottom: top
            ? pw.BorderSide(color: style.bandTextColor, width: 0.3)
            : pw.BorderSide.none,
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: children,
    ),
  );
}

pw.Widget _logo(Uint8List bytes, double height) =>
    pw.Image(pw.MemoryImage(bytes), height: height, fit: pw.BoxFit.contain);
