import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/deck.dart';
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
  final tlp = audience.deck.tlp;
  for (var index = 0; index < images.length; index++) {
    final notes = audience.slides[index].notes;
    if (fonts
        .unsupportedRunes(notes.replaceAll(kRedactionToken, ''))
        .isNotEmpty) {
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
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (tlp != TlpLevel.none)
              pw.Container(
                color: PdfColors.black,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                child: pw.Text(
                  tlp.label,
                  style: pw.TextStyle(
                    font: fonts.mono,
                    fontSize: 9,
                    color: PdfColor.fromInt(tlp.foreground),
                  ),
                ),
              )
            else
              pw.SizedBox(),
            pw.Text('${index + 1} · ${context.pageNumber}'),
          ],
        ),
        build: (_) => [
          pw.Image(image, width: width, height: height, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 18),
          if (notes.isNotEmpty) _notesText(notes),
        ],
      ),
    );
  }
}

/// Het vaste redactietoken wordt getekend, niet aan fontdekking overgelaten.
/// Zo blijven de acht blokken zichtbaar zonder een ontbrekende Unicode-glyph.
pw.RichText _notesText(String notes) {
  final parts = notes.split(kRedactionToken);
  final spans = <pw.InlineSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      spans.add(
        pw.WidgetSpan(
          child: pw.Container(width: 48, height: 11, color: PdfColors.black),
        ),
      );
    }
    if (parts[i].isNotEmpty) spans.add(pw.TextSpan(text: parts[i]));
  }
  return pw.RichText(
    text: pw.TextSpan(children: spans),
    overflow: pw.TextOverflow.span,
  );
}
