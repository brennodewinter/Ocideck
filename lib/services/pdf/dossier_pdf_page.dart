import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';

const _navy = PdfColor.fromInt(0xFF11283D);
const _navySoft = PdfColor.fromInt(0xFF1B3A53);
const _gold = PdfColor.fromInt(0xFFD5A94F);
const _ink = PdfColor.fromInt(0xFF173047);
const _muted = PdfColor.fromInt(0xFF5E7080);
const _paper = PdfColor.fromInt(0xFFF4F6F7);

/// Editorial cover and interleaf for a dossier, sized within the page's
/// existing margins. Its content is already projected for the PDF audience.
pw.Widget buildDossierPdfPage(
  PdfDossierPageBlock block, {
  required DocumentPdfFonts fonts,
  required double width,
  required double height,
}) => block.number == null
    ? _cover(block, fonts, width, height)
    : _interleaf(block, fonts, width, height);

pw.Widget _cover(
  PdfDossierPageBlock block,
  DocumentPdfFonts fonts,
  double width,
  double height,
) => pw.Container(
  width: width,
  height: height,
  padding: const pw.EdgeInsets.all(40),
  decoration: const pw.BoxDecoration(color: _navy),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 48, height: 5, color: _gold),
          pw.SizedBox(height: 24),
          _label('DOCUMENTDOSSIER', fonts, _gold),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text(block.title, fonts, 34, PdfColors.white, bold: true),
          pw.SizedBox(height: 18),
          pw.Container(width: 88, height: 1, color: _gold),
          if (block.description.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _text(block.description, fonts, 13, PdfColors.grey200),
          ],
        ],
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _text('GEORDEND · CONTROLEERBAAR', fonts, 9, PdfColors.grey300),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _text('${block.documentCount}', fonts, 32, _gold, bold: true),
              _label('DOCUMENTEN', fonts, PdfColors.grey300),
            ],
          ),
        ],
      ),
    ],
  ),
);

pw.Widget _interleaf(
  PdfDossierPageBlock block,
  DocumentPdfFonts fonts,
  double width,
  double height,
) => pw.Container(
  width: width,
  height: height,
  decoration: const pw.BoxDecoration(color: _paper),
  child: pw.Row(
    children: [
      pw.Container(width: 10, color: _gold),
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(36, 34, 38, 34),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _label('DOCUMENT', fonts, _muted),
                  pw.SizedBox(height: 4),
                  _text(
                    block.number.toString().padLeft(2, '0'),
                    fonts,
                    62,
                    _navySoft,
                    bold: true,
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(width: 56, height: 4, color: _gold),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text(block.title, fonts, 26, _ink, bold: true),
                  if (block.description.isNotEmpty) ...[
                    pw.SizedBox(height: 18),
                    _text(block.description, fonts, 12, _muted),
                  ],
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(height: 1, color: PdfColors.grey300),
                  pw.SizedBox(height: 16),
                  if (block.date.isNotEmpty) _field('DATUM', block.date, fonts),
                  if (block.author.isNotEmpty)
                    _field('OPSTELLER', block.author, fonts),
                  _label('SHA-256', fonts, _muted),
                  pw.SizedBox(height: 4),
                  _text(block.sha256, fonts, 7.5, _muted, mono: true),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);

pw.Widget _field(String label, String value, DocumentPdfFonts fonts) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 13),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _label(label, fonts, _muted),
          pw.SizedBox(height: 4),
          _text(value, fonts, 11, _ink),
        ],
      ),
    );

pw.Widget _label(String value, DocumentPdfFonts fonts, PdfColor color) =>
    _text(value, fonts, 9, color, bold: true);

pw.Widget _text(
  String value,
  DocumentPdfFonts fonts,
  double size,
  PdfColor color, {
  bool bold = false,
  bool mono = false,
}) => pw.Text(
  value,
  style: pw.TextStyle(
    font: mono ? fonts.mono : (bold ? fonts.headingBold : fonts.base),
    fontFallback: fonts.fallback,
    fontSize: size,
    color: color,
    lineSpacing: 3,
  ),
);
