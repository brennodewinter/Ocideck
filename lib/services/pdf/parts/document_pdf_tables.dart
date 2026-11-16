// Part of the document_pdf_widgets library — see ../document_pdf_widgets.dart.
// Afgesplitst voor navigeerbaarheid en om het tekenbestand onder zijn
// regelplafond te houden: het tabeltekenwerk is een samenhangend geheel dat
// verder niets uit de rest nodig heeft dan de stijl en de spanrenderer.

part of '../document_pdf_widgets.dart';

/// Het tabeltekenwerk van [DocumentPdfWidgets].
///
/// Een extensie en geen losse functies: dit werk heeft de stijl, de
/// spanrenderer en de bladmaten van de bouwer nodig. Een extensie in een
/// `part` deelt de bibliotheekscope en ziet die privéleden dus gewoon,
/// terwijl het tekenbestand zelf onder zijn regelplafond blijft.
extension DocumentPdfTables on DocumentPdfWidgets {
  pw.Widget _table(PdfTableBlock block, {int? rowLimit}) {
    // Een rij die hoger is dan een blad kan `pw.Table` nergens kwijt: hij past
    // op geen enkel blad, dus `MultiPage` blijft bladen openen en de export
    // loopt vast (#1798). Dan gaat de inhoud in een vorm die wél kan breken.
    if (_tableNeedsBlocks(block)) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: _tableAsBlocks(block),
      );
    }
    final rows = <pw.TableRow>[];
    // Past de tabel niet op haar natuurlijke maat, dan krimpt de letter tot ze
    // wél past — evenredig, zodat de verdeling gelijk blijft (#1789, #1794).
    final scale = pdfTableFontScale(
      rows: block.rows,
      colCount: _tableColCount(block),
      tableWidth: maxImageWidth,
      fontSize: style.bodyFontSize,
      cellPadding: style.tableCellPadding,
    );
    for (var index = 0; index < (rowLimit ?? block.rows.length); index++) {
      final isHeader = block.hasHeader && index == 0;
      final zebra = !isHeader && index.isEven ? style.tableZebra : null;
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isHeader ? style.tableHeaderBackground : zebra,
          ),
          repeat: isHeader,
          children: [
            for (var column = 0; column < block.rows[index].length; column++)
              _cell(
                block,
                row: index,
                column: column,
                header: isHeader,
                scale: scale,
              ),
          ],
        ),
      );
    }
    // Kaal en niet in een kader: een tabel is een van de weinige widgets die
    // zichzelf over een bladovergang heen kan verdelen, en die eigenschap
    // verliest hij zodra er iets omheen zit.
    final table = OrphanSafeTable(
      border: _tableBorder(),
      columnWidths: pdfTableColumnWidths(
        rows: block.rows,
        colCount: _tableColCount(block),
        tableWidth: maxImageWidth,
        fontSize: style.bodyFontSize * scale,
        cellPadding: style.tableCellPadding,
      ),
      children: rows,
    );
    return table;
  }

  /// Een tabel met een rij die hoger is dan een blad, gezet als losse blokken.
  ///
  /// Geen tabelvorm, want díe is hier het probleem: een `pw.Table`-rij kan niet
  /// over een bladovergang heen breken, en een rij die op geen enkel blad past
  /// laat de opmaak oneindig rondlopen (#1798).
  ///
  /// De inhoud blijft volledig. Per rij komt elke cel op een eigen regel, met
  /// de kolomkop ervoor wanneer de tabel er een heeft — zo is nog steeds te
  /// zien welk gegeven bij welke kolom hoort. De uitlijning naast elkaar gaat
  /// verloren, maar die was bij een cel van een halve bladzijde toch al geen
  /// leeshulp meer.
  ///
  /// Niets zit hier in een kader of een vaste hoogte: elk stuk moet kunnen
  /// breken, anders is de kwaal terug in een andere vorm.
  /// Of deze tabel een rij draagt die hoger is dan een blad.
  bool _tableNeedsBlocks(PdfTableBlock block) => pdfTableRowExceedsPage(
    block,
    tableWidth: maxImageWidth,
    pageHeight: maxImageHeight,
    fontSize: style.bodyFontSize,
    cellPadding: style.tableCellPadding,
  );

  List<pw.Widget> _tableAsBlocks(PdfTableBlock block) {
    final headers = block.hasHeader && block.rows.isNotEmpty
        ? block.rows.first
        : const <List<PdfSpan>>[];
    final body = block.hasHeader && block.rows.isNotEmpty
        ? block.rows.skip(1)
        : block.rows;
    final out = <pw.Widget>[];
    for (final row in body) {
      for (var column = 0; column < row.length; column++) {
        final label = column < headers.length
            ? headers[column].map((span) => span.text).join().trim()
            : '';
        if (label.isNotEmpty) {
          out.add(
            pw.RichText(
              overflow: pw.TextOverflow.span,
              text: pw.TextSpan(
                style: _baseStyle.copyWith(
                  fontWeight: pw.FontWeight.bold,
                  color: style.subheadingColor,
                ),
                text: label,
              ),
            ),
          );
        }
        out.add(
          pw.RichText(
            overflow: pw.TextOverflow.span,
            text: pw.TextSpan(
              style: _baseStyle.copyWith(color: style.tableText),
              children: _spans(row[column]),
            ),
          ),
        );
        out.add(pw.SizedBox(height: style.bodyFontSize * 0.35));
      }
      out.add(pw.SizedBox(height: style.bodyFontSize * 0.6));
    }
    return out;
  }

  pw.Widget _cell(
    PdfTableBlock block, {
    required int row,
    required int column,
    required bool header,
    double scale = 1,
  }) {
    final alignments = block.alignments;
    final alignment = alignments != null && column < alignments.length
        ? alignments[column]
        : PdfColumnAlignment.left;
    return pw.Padding(
      padding: pw.EdgeInsets.all(style.tableCellPadding),
      child: pw.RichText(
        textAlign: switch (alignment) {
          PdfColumnAlignment.left => pw.TextAlign.left,
          PdfColumnAlignment.center => pw.TextAlign.center,
          PdfColumnAlignment.right => pw.TextAlign.right,
        },
        text: pw.TextSpan(
          style: _baseStyle.copyWith(
            color: header ? style.tableHeaderText : style.tableText,
            fontSize: style.bodyFontSize * scale,
          ),
          children: _spans(block.rows[row][column], scale: scale),
        ),
      ),
    );
  }

  /// De randvorm van tabellen, gelijk aan wat het stijlprofiel op het scherm en
  /// in de LaTeX-export doet: omkaderd, alleen horizontale lijnen, of niets.
  pw.TableBorder? _tableBorder() => switch (style.tableBorderStyle) {
    TableBorderStyle.boxed => pw.TableBorder.all(
      color: style.tableBorderColor,
      width: 0.5,
    ),
    TableBorderStyle.lined => pw.TableBorder.symmetric(
      inside: pw.BorderSide(color: style.tableBorderColor, width: 0.5),
      outside: pw.BorderSide(color: style.tableBorderColor, width: 0.5),
    ),
    TableBorderStyle.none => null,
  };
}
