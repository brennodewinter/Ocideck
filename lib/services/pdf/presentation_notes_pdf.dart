import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../privacy/privacy_projection.dart';
import 'document_pdf_fonts.dart';

/// A4-spreektekst uit precies dezelfde projectie en volgorde als de beelden.
/// Elke dia begint op een nieuw blad; de tekst mag daaronder doorlopen.
void addPresentationNotesPages(
  pw.Document document,
  List<Uint8List> images, {
  required AudienceDeck audience,
  required List<ByteData> fallbackFonts,
}) {
  if (images.length != audience.slides.length) {
    throw ArgumentError('De dia’s en sprekersnotities komen niet overeen.');
  }
  final fonts = DocumentPdfFonts.forFamily(
    'Arial',
    fallbackFonts: fallbackFonts,
  );
  const format = PdfPageFormat.a4;
  const margin = 36.0;
  final width = format.width - 2 * margin;
  final maxImageHeight = (format.height - 2 * margin) * 0.45;
  for (var index = 0; index < images.length; index++) {
    final notes = audience.slides[index].notes;
    if (fonts.unsupportedRunes(notes).isNotEmpty) {
      throw const FormatException(
        'De sprekersnotities bevatten tekens die de PDF-lettertypen niet ondersteunen.',
      );
    }
    final image = pw.MemoryImage(images[index]);
    final height = (width * image.height! / image.width!).clamp(
      1.0,
      maxImageHeight,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        theme: fonts.themeData(fontSize: 11, color: PdfColors.black),
        // Ook een lange alinea mag meer dan de standaard 20 pagina’s vullen.
        // Eén pagina per teken is een bovengrens, geen afkapgrens voor tekst.
        maxPages: notes.length + 20,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${index + 1} · ${context.pageNumber}'),
        ),
        build: (_) => [
          pw.Image(image, width: width, height: height, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 18),
          if (notes.isNotEmpty) pw.Text(notes, overflow: pw.TextOverflow.span),
        ],
      ),
    );
  }
}
