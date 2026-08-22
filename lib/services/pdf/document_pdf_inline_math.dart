import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../../utils/log.dart';
import 'document_pdf_blocks.dart';

/// Zet een formule als SVG in de tekstregel en houdt de TeX als terugval.
pw.InlineSpan buildDocumentPdfInlineMath(
  PdfSpan span, {
  required double fontSize,
  required double maxWidth,
  required Map<String, PdfRenderedGraphic> graphics,
  required pw.InlineSpan Function(String source) fallback,
}) {
  final graphic = graphics[span.text.trim()];
  final svg = graphic?.svg;
  if (svg != null) {
    try {
      var width = graphic?.naturalWidth ?? fontSize * 4;
      var height = graphic?.naturalHeight ?? fontSize * 1.2;
      final heightScale = height > fontSize * 1.5
          ? fontSize * 1.5 / height
          : 1.0;
      final widthScale = width > maxWidth ? maxWidth / width : 1.0;
      final scale = math.min(heightScale, widthScale);
      width *= scale;
      height *= scale;
      return pw.WidgetSpan(
        child: pw.SvgImage(
          svg: svg,
          width: width,
          height: height,
          fit: pw.BoxFit.contain,
        ),
      );
    } catch (error) {
      logWarning(
        'DocumentPdf: inline-formule kon niet worden geplaatst',
        error,
      );
    }
  }
  return fallback('\$${span.text}\$');
}
