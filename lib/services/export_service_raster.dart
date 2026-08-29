// Part of the export_service library — see export_service.dart.
//
// De rasterexports: PDF, PPTX en ODP. Alle drie leveren ze hetzelfde in — de
// dia is een vastgelegd beeld, niet een structuur — en alle drie dragen ze de
// betekenis zo ver als het doelformaat toelaat. Hier apart gezet omdat
// export_service.dart tegen zijn regelplafond aan liep; het is één onderwerp,
// geen willekeurige snee.
part of 'export_service.dart';

/// De sprekersnotities van de geprojecteerde slides, in dezelfde volgorde als
/// de gerasterde beelden — het PPTX-notitiepaneel koppelt op index.
List<String>? _notesOf(ExportBundle? audience) => audience == null
    ? null
    : [for (final s in audience.audience.slides) s.notes];

/// De alt-tekst per slide voor een raster-export (IMAGE_CALLOUTS.md §12.2):
/// de bestaande alt-tekst van de afbeelding met de callout-beschrijvingen
/// erachter. Een gerasterde slide blijft structureel ontoegankelijk; dit
/// voorkomt alleen dat de betekenis wegvalt waar het formaat er een sleuf
/// voor heeft. Een geredigeerde slide levert niets — dan staat het beeld er
/// ook niet meer.
List<String>? _altTextsOf(ExportBundle? audience) => audience == null
    ? null
    : [
        for (final s in audience.audience.slides)
          s.mediaRedacted || s.contentRedacted
              ? ''
              : calloutAltText(s.imageAltText, s.callouts),
      ];

/// De PPTX-bouw, van de switch afgehaald zodat [export] onder het
/// methodeplafond blijft. Spreektekst en alt-tekst komen uit hetzelfde
/// geprojecteerde deck.
Future<Uint8List> _buildPptx(
  List<Uint8List> images, {
  required ExportDocumentMetadata metadata,
  required String fallbackTitle,
  required ExportBundle? audience,
}) => ExportService._offload(
  () => buildDeckExportPptx(
    images,
    metadata: metadata,
    fallbackTitle: fallbackTitle,
    notes: _notesOf(audience),
    altTexts: _altTextsOf(audience),
  ),
);

/// De ODP-bouw. ODP kent geen notitieblad in deze export; alleen de
/// alt-tekstsleuf reist mee.
Future<Uint8List> _buildOdp(
  List<Uint8List> images, {
  required ExportDocumentMetadata metadata,
  required String fallbackTitle,
  required ExportBundle? audience,
}) => ExportService._offload(
  () => buildDeckExportOdp(
    images: images,
    metadata: metadata,
    fallbackTitle: fallbackTitle,
    altTexts: _altTextsOf(audience),
  ),
);

Future<Uint8List> _buildPdf(
  List<Uint8List> images, {
  required ExportDocumentMetadata metadata,
  required String fallbackTitle,
  bool compress = false,
}) {
  return ExportService._offload(() async {
    final doc = pw.Document(
      title: metadata.displayTitle(fallbackTitle),
      author: metadata.documentAuthor,
      subject: metadata.subject(fallbackTitle),
      keywords: metadata.exportKeywords(),
      creator: metadata.creator,
      producer: metadata.producer,
    );
    // Page size in points; only the ratio matters for a full-bleed image.
    const format = PdfPageFormat(1280, 720, marginAll: 0);
    for (final png in images) {
      // MemoryImage auto-detects PNG vs JPEG from the byte header, so a
      // compressed (JPEG) slide embeds just like the lossless one.
      final image = pw.MemoryImage(compress ? _toJpeg(png) : png);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
    return doc.save();
  });
}

/// Downscale a rendered slide PNG to [ExportService._compressedMaxWidth] and re-encode it as
/// JPEG at [ExportService._compressedJpegQuality]. Slides are full-bleed (no transparency),
/// so dropping the alpha channel is safe.
Uint8List _toJpeg(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) return png; // Unexpected; keep the original bytes.
  final resized = decoded.width > ExportService._compressedMaxWidth
      ? img.copyResize(
          decoded,
          width: ExportService._compressedMaxWidth,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  return img.encodeJpg(resized, quality: ExportService._compressedJpegQuality);
}
