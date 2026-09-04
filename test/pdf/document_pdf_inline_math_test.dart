import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_inline_math.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  ByteData roboto() => File(
    'assets/fonts/Roboto-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  DocumentPdfFonts fonts({bool withFallback = true}) =>
      DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: withFallback ? [roboto()] : const [],
      );

  test('een inline-formule zakt van de onderrand naar de tekstbaseline', () {
    final result = buildDocumentPdfInlineMath(
      const PdfSpan('E = mc^2', math: true),
      fontSize: 11,
      maxWidth: 200,
      graphics: const {
        'E = mc^2': PdfRenderedGraphic.svg(
          '<svg viewBox="0 0 96 18"><text y="14">E = mc2</text></svg>',
          naturalWidth: 96,
          naturalHeight: 18,
        ),
      },
      fonts: fonts(),
      fallback: (source) => pw.TextSpan(text: source),
    );

    expect(result, isA<pw.WidgetSpan>());
    expect((result as pw.WidgetSpan).baseline, lessThan(0));
  });

  // MathJax zet zijn glyphs als `<path>`, maar een `\text{…}` komt er als echte
  // `<text>` uit — en dan geldt de Latin-1-grens van de SVG-lezer ook hier
  // (#1942). Zonder snede die het teken kan zetten hoort de TeX in de zin te
  // blijven staan, want de worp zou pas bij `save()` komen.
  test('zonder Unicode-snede blijft een formule met zulke tekens TeX', () {
    pw.InlineSpan build({
      required bool withFallback,
    }) => buildDocumentPdfInlineMath(
      const PdfSpan(r'x \text{— per kwartaal}', math: true),
      fontSize: 11,
      maxWidth: 200,
      graphics: const {
        r'x \text{— per kwartaal}': PdfRenderedGraphic.svg(
          '<svg viewBox="0 0 96 18"><text y="14">x — per kwartaal</text></svg>',
          naturalWidth: 96,
          naturalHeight: 18,
        ),
      },
      fonts: fonts(withFallback: withFallback),
      fallback: (source) => pw.TextSpan(text: source),
    );

    expect(build(withFallback: false), isA<pw.TextSpan>());
    // Mét die snede wordt de formule wél gezet.
    expect(build(withFallback: true), isA<pw.WidgetSpan>());
  });
}
