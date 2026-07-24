import 'dart:math' as math;

import 'text_measurement.dart';

/// Celmarges van de tabelpreview, hier gedeeld zodat meten en tekenen over
/// dezelfde geometrie praten. Zie `table_preview.dart`.
const double kTableCellHPadFactor = 0.55;
const double kTableCellVPadFactor = 0.36;
const double kTableCellLineHeight = 1.25;

/// Table cell font size fraction used in [table_preview.dart].
double tableCellFontSize(
  double w, {
  required int rowCount,
  required int colCount,
}) {
  final density = (rowCount + colCount).clamp(2, 24);
  return (w * 0.025 * (10 / (density + 6))).clamp(w * 0.010, w * 0.021);
}

/// Minimum table cell font fraction (lower clamp bound in previews).
double tableCellFontMinimum(double w) => w * 0.010;

/// Per-column flex weights: each column's longest cell length (trimmed),
/// clamped so a single paragraph-length outlier can't starve its neighbours.
/// These divide the room that is left *after* every column has its minimum —
/// see [tableColumnWidths], which is what both the measurement and the render
/// actually use.
List<double> tableColumnFlexWeights(List<List<String>> rows, int colCount) {
  return <double>[
    for (var c = 0; c < colCount; c++)
      rows
          .map((r) => c < r.length ? r[c].trim().length : 0)
          .fold<int>(1, (longest, len) => len > longest ? len : longest)
          .clamp(1, 80)
          .toDouble(),
  ];
}

/// De breedte waaronder kolom [c] haar eigen kop niet meer heel kan tonen.
///
/// Een kop als "Systemen" telt vier tekens minder dan "Finding" maar is breder;
/// puur op tekenaantal verdeeld kreeg zo'n kolom minder ruimte dan het woord
/// nodig heeft, brak hij letter voor letter af, en zodra de kolom smaller werd
/// dan haar eigen celmarge tekende de tekst dwars over de tabellijnen. Vandaar
/// een ondergrens van marge + het breedste ondeelbare woord, met minimaal één
/// em zodat ook een lege kop nog ruimte voor een teken houdt.
double _columnMinWidth(
  List<String> header,
  int c,
  double cellSize,
  String font,
) {
  final text = c < header.length ? header[c].trim() : '';
  final word = text.isEmpty
      ? 0.0
      : measureTextWordWidth(text, cellSize, bold: true, fontFamily: font);
  return cellSize * kTableCellHPadFactor * 2 + math.max(cellSize, word);
}

/// Kolombreedtes in pixels, samen precies [tableWidth] breed.
///
/// Elke kolom krijgt eerst haar ondergrens ([_columnMinWidth]); wat overblijft
/// wordt verdeeld naar [tableColumnFlexWeights], zodat een tekstrijke kolom nog
/// steeds het leeuwendeel pakt zonder de smalle kolommen plat te drukken.
List<double> tableColumnWidths({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double cellSize,
  required String font,
}) {
  if (rows.isEmpty || colCount <= 0 || tableWidth <= 0) {
    return List<double>.filled(math.max(colCount, 0), 0);
  }
  final header = rows.first;
  final minimums = <double>[
    for (var c = 0; c < colCount; c++)
      _columnMinWidth(header, c, cellSize, font),
  ];
  final minimumSum = minimums.fold<double>(0, (a, b) => a + b);
  // Meer koptekst dan er breedte is: dan wint de tabelbreedte. Een gebroken kop
  // is lelijk, buiten de slide tekenen is fout.
  if (minimumSum >= tableWidth) {
    return _scaledToFit(minimums, minimumSum, tableWidth);
  }
  final weights = tableColumnFlexWeights(rows, colCount);
  final weightSum = weights.fold<double>(0, (a, b) => a + b);
  final free = tableWidth - minimumSum;
  final widths = <double>[
    for (var c = 0; c < colCount; c++)
      minimums[c] + free * weights[c] / weightSum,
  ];
  return _scaledToFit(
    widths,
    widths.fold<double>(0, (a, b) => a + b),
    tableWidth,
  );
}

/// Schaalt de som exact terug naar [tableWidth]. De verdeling komt er al op uit;
/// dit vangt de laatste afrondingsbits, want een Table met vaste kolommen die
/// samen één micron te breed zijn tekent buiten haar doos.
List<double> _scaledToFit(
  List<double> widths,
  double total,
  double tableWidth,
) {
  if (total <= 0) return widths;
  final factor = tableWidth / total;
  return [for (final width in widths) width * factor];
}

/// Rendered height of the table body at [cellSize], laid out at [tableWidth]
/// with the columns from [tableColumnWidths]. The per-cell padding mirrors
/// table_preview.dart so the measured height matches what is drawn.
double tableBlockHeight({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double cellSize,
  required String font,
}) {
  if (rows.isEmpty || colCount <= 0) return 0;
  final colW = tableColumnWidths(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    cellSize: cellSize,
    font: font,
  );
  final hPad = cellSize * kTableCellHPadFactor;
  final vPad = cellSize * kTableCellVPadFactor;
  var height = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final header = i == 0;
    var rowH = 0.0;
    for (var c = 0; c < colCount; c++) {
      final text = c < row.length ? row[c] : '';
      final innerW = math.max(1.0, colW[c] - hPad * 2);
      final h = measureTextHeight(
        text.isEmpty ? ' ' : text,
        cellSize,
        innerW,
        lineHeight: kTableCellLineHeight,
        bold: header,
        fontFamily: font,
      );
      if (h > rowH) rowH = h;
    }
    height += rowH + vPad * 2;
  }
  return height;
}

/// Largest cell font in [minCellSize, baseCellSize] whose table body fits
/// [availH] at [tableWidth]. A text-heavy table shrinks its font so it fills
/// the slide's full width, instead of being scaled down — and thereby narrowed
/// — uniformly by the preview's FittedBox.
double tableFitCellSize({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double availH,
  required double baseCellSize,
  required double minCellSize,
  required String font,
  double fillRatio = 0.98,
}) {
  if (rows.isEmpty || colCount <= 0 || availH <= 0) return baseCellSize;
  double measure(double size) => tableBlockHeight(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    cellSize: size,
    font: font,
  );
  var size = baseCellSize;
  // Shrinking the font also narrows each cell's text, so a row's height drops
  // a little faster than linearly; the height-ratio step converges in a few
  // passes. One measure() per iteration (mirrors tightenVerticalFitScale).
  while (size > minCellSize + 0.05) {
    final h = measure(size);
    if (h <= availH * fillRatio) break;
    final next = (size * availH / h * fillRatio).clamp(minCellSize, size);
    if ((size - next).abs() < 0.05) {
      size = next;
      break;
    }
    size = next;
  }
  return size.clamp(minCellSize, baseCellSize);
}
