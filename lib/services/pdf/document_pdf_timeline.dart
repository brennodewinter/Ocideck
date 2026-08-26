import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_pdf_blocks.dart';
import 'document_pdf_style.dart';

typedef PdfTimelineText =
    pw.Widget Function(
      List<PdfSpan> spans,
      pw.TextStyle textStyle, {
      pw.TextAlign? align,
    });

/// Tekent de schermtaal van een documenttijdlijn met PDF-primitieven.
pw.Widget buildDocumentPdfTimeline(
  PdfTimelineBlock block, {
  required DocumentPdfStyle style,
  required pw.TextStyle baseStyle,
  required PdfTimelineText text,
}) {
  final size = style.bodyFontSize;
  final headerStyle = baseStyle.copyWith(
    fontSize: size * 0.65,
    fontWeight: pw.FontWeight.bold,
    color: style.subheadingColor,
  );
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // De kop van de tijdkolom hoort bij de tijdlijn, niet bij de kaart.
      // Hij stond boven élke kaart, en met een beschrijvende kop als "Lokale
      // tijd (CEST, UTC+02:00)" was dat vijftig keer dezelfde regel in acht
      // bladzijden (#1793). Eén keer, boven de kolom waar hij over gaat.
      if (block.headers.first.isNotEmpty) ...[
        pw.SizedBox(
          width: size * 8.2,
          child: pw.Padding(
            padding: pw.EdgeInsets.only(right: size * 2.5),
            child: pw.Text(
              block.headers.first,
              style: headerStyle,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ),
        pw.SizedBox(height: size * 0.4),
      ],
      for (var index = 0; index < block.events.length; index++)
        _event(block, index, style: style, baseStyle: baseStyle, text: text),
    ],
  );
}

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
  // Een rij is op zichzelf een verticale Flex en kan daardoor over twee
  // pagina's worden gesplitst. Dan begint de tweede helft boven de bladrand en
  // verdwijnen label en begin van de kaart. Een gebeurtenis is één kaart en
  // verhuist daarom als geheel naar het volgende blad.
  //
  // De rail wordt als pw.Positioned in een pw.Stack getekend, zodat hij de
  // volle hoogte van de kaart vult en doorloopt naar het volgende event. De
  // tussentijdse spacing zit in de kaart-margin, niet in een outer Padding —
  // zo loopt de rail erdoorheen en is hij ononderbroken (#1724). pw.Expanded
  // in een Column werkt hier niet omdat MultiPage onbegrenste hoogte geeft;
  // pw.Positioned met top+bottom wél, omdat de Stack zijn hoogte haalt uit
  // het niet-positioneerde kind (de Row met de kaart).
  final labelWidth = size * 8.2;
  final railWidth = size * 2.2;
  final railX = labelWidth + size * 0.55;
  final dotSize = size * 0.86;
  final dotTop = first ? 0.0 : size * 0.8;
  final dotBottom = dotTop + dotSize;

  return pw.Inseparable(
    child: pw.Stack(
      children: [
        _eventCard(
          block,
          event,
          style: style,
          baseStyle: baseStyle,
          labelStyle: labelStyle,
          text: text,
          size: size,
          labelWidth: labelWidth,
          railWidth: railWidth,
          last: last,
        ),
        ..._eventMarkers(
          style: style,
          size: size,
          labelWidth: labelWidth,
          railWidth: railWidth,
          railX: railX,
          dotSize: dotSize,
          dotTop: dotTop,
          dotBottom: dotBottom,
          first: first,
          last: last,
        ),
      ],
    ),
  );
}

/// De kaart met label en inhoud — het niet-positioneerbare kind dat de Stack
/// zijn afmetingen geeft.
pw.Widget _eventCard(
  PdfTimelineBlock block,
  PdfTimelineEvent event, {
  required DocumentPdfStyle style,
  required pw.TextStyle baseStyle,
  required pw.TextStyle labelStyle,
  required PdfTimelineText text,
  required double size,
  required double labelWidth,
  required double railWidth,
  required bool last,
}) => pw.Padding(
  padding: pw.EdgeInsets.only(bottom: last ? size * 0.7 : size * 0.9),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: labelWidth,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(top: size * 0.65, right: size * 2.5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              // Rechts uitgelijnd, óók wanneer de tijd over twee regels
              // breekt. Zonder dit stond een korte tijd rechts en een lange
              // links, en oogde de kolom rafelig (#1793).
              text(
                event.marker,
                labelStyle.copyWith(fontSize: size * 0.81),
                align: pw.TextAlign.right,
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: railWidth),
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
              if (block.headers.length > 1 && block.headers[1].isNotEmpty) ...[
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

/// De rail, het bolletje en de verbindingsstreep — positioneerbare kinderen
/// die over de volle hoogte van de kaart worden getekend.
List<pw.Widget> _eventMarkers({
  required DocumentPdfStyle style,
  required double size,
  required double labelWidth,
  required double railWidth,
  required double railX,
  required double dotSize,
  required double dotTop,
  required double dotBottom,
  required bool first,
  required bool last,
}) => [
  // Verticale rail: loopt van de bovenkant (of onder het bolletje op het
  // eerste event) tot de onderkant van de kaart, zodat hij aansluit op het
  // volgende event.
  if (!last)
    pw.Positioned(
      left: railX,
      top: first ? dotBottom : 0,
      bottom: 0,
      child: pw.Container(width: 1.5, color: style.tableBorderColor),
    ),
  // Eindmarkering op het laatste event: een horizontale dwarsstreep onder
  // het bolletje (┷) die aangeeft dat de tijdlijn klaar is.
  if (last)
    pw.Positioned(
      left: labelWidth + size * 0.15,
      top: dotBottom,
      child: pw.Container(
        width: size * 0.82,
        height: 1.5,
        color: style.tableBorderColor,
      ),
    ),
  // Bolletje met witte vulkleur zodat de rail erachter bedekt is.
  pw.Positioned(
    left: labelWidth,
    top: dotTop,
    child: pw.Container(
      width: dotSize,
      height: dotSize,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: style.accentColor, width: 2.2),
      ),
    ),
  ),
  // Horizontale verbinding tussen bolletje en kaart.
  pw.Positioned(
    left: labelWidth + dotSize,
    top: dotTop + dotSize / 2 - 0.75,
    child: pw.Container(
      width: railWidth - dotSize,
      height: 1.5,
      color: style.tableBorderColor,
    ),
  ),
];
