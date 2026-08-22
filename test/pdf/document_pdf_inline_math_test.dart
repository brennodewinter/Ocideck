import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_inline_math.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
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
      fallback: (source) => pw.TextSpan(text: source),
    );

    expect(result, isA<pw.WidgetSpan>());
    expect((result as pw.WidgetSpan).baseline, lessThan(0));
  });
}
