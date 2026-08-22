import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_pdf_blocks.dart';
import 'document_pdf_style.dart';

typedef PdfTimelineText =
    pw.Widget Function(List<PdfSpan> spans, pw.TextStyle textStyle);

/// Tekent de schermtaal van een documenttijdlijn met PDF-primitieven.
pw.Widget buildDocumentPdfTimeline(
  PdfTimelineBlock block, {
  required DocumentPdfStyle style,
  required pw.TextStyle baseStyle,
  required PdfTimelineText text,
}) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    for (var index = 0; index < block.events.length; index++)
      _event(block, index, style: style, baseStyle: baseStyle, text: text),
  ],
);

pw.Widget _event(
  PdfTimelineBlock block,
  int index, {
  required DocumentPdfStyle style,
  required pw.TextStyle baseStyle,
  required PdfTimelineText text,
}) {
  final event = block.events[index];
  final size = style.bodyFontSize;
  final first = index == 0;
  final last = index == block.events.length - 1;
  final labelStyle = baseStyle.copyWith(
    fontSize: size * 0.65,
    fontWeight: pw.FontWeight.bold,
    color: style.subheadingColor,
  );
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: last ? size * 0.7 : size * 0.9),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: size * 8.2,
          child: pw.Padding(
            padding: pw.EdgeInsets.only(top: size * 0.65, right: size * 2.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (block.headers.first.isNotEmpty)
                  pw.Text(block.headers.first, style: labelStyle),
                text(event.marker, labelStyle.copyWith(fontSize: size * 0.81)),
              ],
            ),
          ),
        ),
        pw.SizedBox(
          width: size * 2.2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (!first)
                pw.Padding(
                  padding: pw.EdgeInsets.only(left: size * 0.55),
                  child: pw.Container(
                    width: 1.5,
                    height: size * 0.8,
                    color: style.tableBorderColor,
                  ),
                ),
              pw.Row(
                children: [
                  pw.Container(
                    width: size * 0.86,
                    height: size * 0.86,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(
                        color: style.accentColor,
                        width: 2.2,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      height: 1.5,
                      color: style.tableBorderColor,
                    ),
                  ),
                ],
              ),
              pw.Padding(
                padding: pw.EdgeInsets.only(
                  left: last ? size * 0.15 : size * 0.55,
                ),
                child: pw.Container(
                  width: last ? size * 0.82 : 1.5,
                  height: last ? 1.5 : size * 3.1,
                  color: style.tableBorderColor,
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            padding: pw.EdgeInsets.all(size * 0.85),
            decoration: pw.BoxDecoration(
              color: style.quoteBackground,
              border: pw.Border.all(color: style.tableBorderColor, width: 0.7),
              borderRadius: pw.BorderRadius.circular(size * 0.65),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (block.headers.length > 1 &&
                    block.headers[1].isNotEmpty) ...[
                  pw.Text(block.headers[1].toUpperCase(), style: labelStyle),
                  pw.SizedBox(height: size * 0.3),
                ],
                text(event.event, baseStyle),
                if (event.metadata != null) ...[
                  pw.SizedBox(height: size * 0.55),
                  pw.Container(
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: size * 0.55,
                      vertical: size * 0.25,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: style.tableBorderColor,
                        width: 0.6,
                      ),
                      borderRadius: pw.BorderRadius.circular(size),
                    ),
                    child: text([
                      if (block.headers.length > 2)
                        PdfSpan('${block.headers[2]}: ', bold: true),
                      ...event.metadata!,
                    ], baseStyle.copyWith(fontSize: size * 0.74)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
