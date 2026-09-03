import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../../utils/log.dart';
import 'document_pdf_blocks.dart';
import 'document_pdf_fonts.dart';

/// Zet een formule als SVG in de tekstregel en houdt de TeX als terugval.
pw.InlineSpan buildDocumentPdfInlineMath(
  PdfSpan span, {
  required double fontSize,
  required double maxWidth,
  required Map<String, PdfRenderedGraphic> graphics,
  required DocumentPdfFonts fonts,
  required pw.InlineSpan Function(String source) fallback,
}) {
  final graphic = graphics[span.text.trim()];
  final svg = graphic?.svg;
  // MathJax zet zijn glyphs als `<path>`, maar een `\text{…}` komt er als
  // echte `<text>` uit — en dan geldt de Latin-1-grens van de SVG-lezer ook
  // hier. Zie [DocumentPdfFonts.svgFont]; zonder passende snede blijft de TeX
  // in de zin staan, wat sowieso de terugval van dit bestand is.
  final typesetting = svg == null ? null : fonts.svgTypesetting(svg);
  final svgFont = typesetting?.font;
  if (svg != null && typesetting!.settable) {
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
        // Een SVG-kader eindigt onder zijn getekende glyphs (MathJax bewaart
        // ruimte voor staarten). De standaard-baseline zet die kaderrand op de
        // tekstbaseline en laat de formule daardoor zweven. Een kleine daling
        // brengt de zichtbare tekens op dezelfde lijn als het omringende proza.
        baseline: -fontSize * 0.22,
        child: pw.SvgImage(
          svg: svg,
          width: width,
          height: height,
          fit: pw.BoxFit.contain,
          customFontLookup: svgFont == null ? null : (_, _, _) => svgFont,
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
