import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/document_pdf_timeline.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('iedere tijdlijnkaart blijft heel bij een paginaovergang', () {
    final timeline =
        buildDocumentPdfTimeline(
              const PdfTimelineBlock(
                ['Tijd', 'Gebeurtenis'],
                [
                  PdfTimelineEvent([PdfSpan('09:00')], [PdfSpan('Begin')]),
                  PdfTimelineEvent([PdfSpan('10:00')], [PdfSpan('Vervolg')]),
                ],
              ),
              style: DocumentPdfStyle.fromTheme(const ThemeProfile()),
              baseStyle: const pw.TextStyle(fontSize: 11),
              text: (spans, style) =>
                  pw.Text(spans.map((span) => span.text).join(), style: style),
            )
            as pw.Column;

    expect(timeline.children, everyElement(isA<pw.Inseparable>()));
  });
}
