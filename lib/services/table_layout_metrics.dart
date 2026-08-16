import 'dart:math' as math;

import 'text_measurement.dart';

/// Celmarges van de tabelpreview, hier gedeeld zodat meten en tekenen over
/// dezelfde geometrie praten. Zie `table_preview.dart`.
const double kTableCellHPadFactor = 0.55;
const double kTableCellVPadFactor = 0.36;
const double kTableCellLineHeight = 1.25;

/// Minimum table cell font fraction (lower clamp bound in previews).
double tableCellFontMinimum(double w) => w * 0.010;

/// Bovengrens voor een tabelcel.
///
/// Een tabel mag de dia vullen in plaats van als fragment bovenin te blijven
/// hangen, maar celtekst blijft bijtekst: nooit groter dan een opsommingsregel
/// ([kBulletMaxFontFraction], 0,0335). Zonder plafond zou een tabel van twee
/// regels zichzelf tot koptekst opblazen.
double tableCellFontMaximum(double w) => w * 0.028;

/// De horizontale celmarge per zijde bij [cellSize].
///
/// De preview leidt haar marge af uit de letter ([kTableCellHPadFactor]); de
/// documentweergave hanteert een vaste marge uit het stijlprofiel. Wie meet
/// moet dezelfde marge hanteren als wie tekent — anders rekent de maatvoering
/// zich rijker dan de cel is en breekt de tekst alsnog middenin een woord.
double tableCellHPad(double cellSize, [double? hPadOverride]) =>
    hPadOverride ?? cellSize * kTableCellHPadFactor;

/// De ruimte die alle kolommen samen minstens opeisen bij [cellSize] — marge
/// plus het breedste ondeelbare kopwoord per kolom. Zie [tableColumnWidths].
double tableColumnMinimumsWidth({
  required List<List<String>> rows,
  required int colCount,
  required double cellSize,
  required String font,
  double? hPad,
}) {
  if (rows.isEmpty || colCount <= 0) return 0;
  final header = rows.first;
  var total = 0.0;
  for (var c = 0; c < colCount; c++) {
    total += _columnMinWidth(header, c, cellSize, font, hPad);
  }
  return total;
}

/// De grootste celgrootte waarbij de kolomminima nog samen binnen
/// [tableWidth] × [headroom] blijven.
///
/// Groeit de letter door tot voorbij die grens, dan wordt elke kolom naar haar
/// eigen kop teruggeschaald en houdt de inhoud niets over — precies de klem
/// waar [tableColumnWidths] voor bestaat. De minima schalen lineair mee met de
/// celgrootte, dus één meting bij [probeCellSize] volstaat.
double tableWidthCappedCellSize({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double probeCellSize,
  required String font,
  double headroom = 0.8,
  double? hPad,
}) {
  final probe = tableColumnMinimumsWidth(
    rows: rows,
    colCount: colCount,
    cellSize: probeCellSize,
    font: font,
    hPad: hPad,
  );
  if (probe <= 0) return double.infinity;
  return probeCellSize * tableWidth * headroom / probe;
}

/// De extra verticale celmarge waarmee een tabel die na het lettergroeien nog
/// ruimte overhoudt, zich over [availH] uitspreidt.
///
/// De letter loopt tegen [tableCellFontMaximum] aan voordat een korte tabel de
/// dia vult; de rest wordt over de rijen verdeeld in plaats van als gat onderaan
/// te blijven staan. Begrensd op één em per zijde, zodat drie regels luchtige
/// banden worden en geen uitgerekte strepen.
double tableExtraRowPadding({
  required double blockHeight,
  required double availH,
  required int rowCount,
  required double cellSize,
}) {
  if (rowCount <= 0 || blockHeight <= 0 || availH <= blockHeight) return 0;
  final perSide = (availH - blockHeight) / rowCount / 2;
  return math.min(perSide, cellSize);
}

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
  String font, [
  double? hPad,
]) {
  final text = c < header.length ? header[c].trim() : '';
  final word = text.isEmpty
      ? 0.0
      : measureTextWordWidth(text, cellSize, bold: true, fontFamily: font);
  return tableCellHPad(cellSize, hPad) * 2 + math.max(cellSize, word);
}

/// De breedte waarbij kolom [c] geen enkel woord meer hoeft te breken: marge
/// plus het breedste ondeelbare woord over álle rijen.
///
/// Dit is een *wens*, geen ondergrens ([_columnMinWidth] is dat wel). De
/// kolomverdeling verdeelde de vrije ruimte naar tekenaantal, en dat is net
/// niet hetzelfde als breedte: een kolom kon een paar pixels tekortkomen en
/// dan één letter van het laatste woord naar de volgende regel duwen. Precies
/// dat leest slecht in een tabel, dus krijgt elke kolom eerst haar woordwens
/// voordat de rest naar tekenaantal wordt verdeeld.
double _columnWordWidth(
  List<List<String>> rows,
  int c,
  double cellSize,
  String font,
  double? hPad,
) {
  var widest = 0.0;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final text = c < row.length ? row[c].trim() : '';
    if (text.isEmpty) continue;
    final word = measureTextWordWidth(
      text,
      cellSize,
      bold: r == 0,
      fontFamily: font,
    );
    if (word > widest) widest = word;
  }
  return tableCellHPad(cellSize, hPad) * 2 + widest;
}

/// Verdeelt [free] pixels over de wensen in [needs] volgens max-min-eerlijkheid:
/// iedereen krijgt een gelijk deel, wie minder nodig heeft dan dat neemt alleen
/// wat hij nodig heeft, en wat hij laat liggen gaat naar wie nog tekortkomt.
///
/// Naar rato verdelen zou hier het verkeerde doen: één cel met een URL die
/// sowieso niet heel kan, heeft een wens zo groot dat hij naar rato álles
/// opslokt — en dan breekt de buurkolom met een doodgewoon woord alsnog. Zo
/// worden juist de bescheiden wensen eerst ingewilligd en draagt de uitschieter
/// het tekort, wat precies de kolom is waar de breuk toch onvermijdelijk is.
List<double> _maxMinFill(List<double> needs, double free) {
  final grants = List<double>.filled(needs.length, 0);
  final open = <int>[
    for (var i = 0; i < needs.length; i++)
      if (needs[i] > 0) i,
  ];
  var left = free;
  while (open.isNotEmpty && left > 1e-9) {
    final share = left / open.length;
    // Niemand blijft onder zijn deel: dan is er niets meer te herverdelen en
    // krijgt iedereen gewoon dat deel.
    final satisfied = open.where((i) => needs[i] - grants[i] <= share).toList();
    if (satisfied.isEmpty) {
      for (final i in open) {
        grants[i] += share;
      }
      return grants;
    }
    for (final i in satisfied) {
      left -= needs[i] - grants[i];
      grants[i] = needs[i];
      open.remove(i);
    }
  }
  return grants;
}

/// Kolombreedtes in pixels, samen precies [tableWidth] breed.
///
/// In drie stappen: elke kolom krijgt haar ondergrens ([_columnMinWidth]),
/// daarna zoveel mogelijk van haar woordwens ([_columnWordWidth]) zodat geen
/// woord middenin hoeft te breken, en pas wat dán nog vrij is wordt verdeeld
/// naar [tableColumnFlexWeights] — zodat een tekstrijke kolom nog steeds het
/// leeuwendeel pakt zonder de smalle kolommen plat te drukken.
///
/// [hPad] is de horizontale celmarge per zijde; laat hem weg wanneer de
/// tekenaar de marge uit de letter afleidt ([kTableCellHPadFactor]).
List<double> tableColumnWidths({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double cellSize,
  required String font,
  double? hPad,
}) {
  if (rows.isEmpty || colCount <= 0 || tableWidth <= 0) {
    return List<double>.filled(math.max(colCount, 0), 0);
  }
  final header = rows.first;
  final minimums = <double>[
    for (var c = 0; c < colCount; c++)
      _columnMinWidth(header, c, cellSize, font, hPad),
  ];
  final minimumSum = minimums.fold<double>(0, (a, b) => a + b);
  // Meer koptekst dan er breedte is: dan wint de tabelbreedte. Een gebroken kop
  // is lelijk, buiten de slide tekenen is fout.
  if (minimumSum >= tableWidth) {
    return _scaledToFit(minimums, minimumSum, tableWidth);
  }
  final free = tableWidth - minimumSum;
  final grants = _maxMinFill([
    for (var c = 0; c < colCount; c++)
      math.max(
        0.0,
        _columnWordWidth(rows, c, cellSize, font, hPad) - minimums[c],
      ),
  ], free);
  final wanted = <double>[
    for (var c = 0; c < colCount; c++) minimums[c] + grants[c],
  ];
  final wantedSum = wanted.fold<double>(0, (a, b) => a + b);
  // Alle vrije ruimte ging al op aan het heel houden van woorden: dan is er
  // niets meer om naar tekenaantal te verdelen.
  if (wantedSum >= tableWidth - 1e-9) {
    return _scaledToFitAll(wanted, tableWidth);
  }
  final weights = tableColumnFlexWeights(rows, colCount);
  final weightSum = weights.fold<double>(0, (a, b) => a + b);
  final surplus = tableWidth - wantedSum;
  return _scaledToFitAll([
    for (var c = 0; c < colCount; c++)
      wanted[c] + surplus * weights[c] / weightSum,
  ], tableWidth);
}

List<double> _scaledToFitAll(List<double> widths, double tableWidth) =>
    _scaledToFit(widths, widths.fold<double>(0, (a, b) => a + b), tableWidth);

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
/// [extraVPad] is de opvulmarge uit [tableExtraRowPadding]; meten en tekenen
/// moeten dezelfde marge hanteren.
double tableBlockHeight({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double cellSize,
  required String font,
  double extraVPad = 0,
  double? hPadOverride,
}) {
  if (rows.isEmpty || colCount <= 0) return 0;
  final colW = tableColumnWidths(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    cellSize: cellSize,
    font: font,
    hPad: hPadOverride,
  );
  final hPad = tableCellHPad(cellSize, hPadOverride);
  final vPad = cellSize * kTableCellVPadFactor + extraVPad;
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
///
/// [baseCellSize] is het plafond waar vanaf gezocht wordt, niet een streefmaat:
/// geef er [tableCellFontMaximum] aan (begrensd door
/// [tableWidthCappedCellSize]) en een tabel die ruimte over heeft groeit
/// erheen in plaats van als fragment bovenin de dia te blijven hangen.
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

/// De hoogte die een tabel op een referentiedia krijgt: de 16:9-doos min de
/// standaardranden en een titelblok van één regel.
///
/// Met opzet een benadering. De kwaliteitscontrole kent het thema, het logo en
/// de titelafbreking van de gebruiker niet, en oordeelt dus over een
/// representatieve dia in plaats van over dé dia. De schatting is aan de ruime
/// kant: liever een waarschuwing te weinig dan een die te vaak afgaat, want die
/// laatste waarschuwt nergens meer voor.
double tableReferenceAvailableHeight(double w) {
  final pad = w * 0.06;
  return w * 9 / 16 - pad * 2 - (w * 0.038 * kTableCellLineHeight + pad * 0.35);
}

/// De tabelbreedte op diabreedte [w], met de standaardranden eraf.
double tableReferenceWidth(double w) => w - w * 0.06 * 2;

/// De volledige maatvoering van een tabelblok binnen [availH]: de grootste
/// celgrootte die past, plus de marge waarmee wat dan nog overblijft over de
/// rijen wordt verdeeld.
///
/// De letter groeit tot [tableCellFontMaximum], of tot de kolomminima de
/// tabelbreedte opeten ([tableWidthCappedCellSize]) — wat het eerst komt. Wat
/// een korte tabel daarna nog aan hoogte overhoudt, gaat naar de rijen zelf, in
/// plaats van als gat onder de tabel te blijven staan.
({double cellSize, double extraVPad}) tableFit({
  required List<List<String>> rows,
  required int colCount,
  required double slideWidth,
  required double tableWidth,
  required double availH,
  required String font,
}) {
  final maxCell = math.min(
    tableCellFontMaximum(slideWidth),
    tableWidthCappedCellSize(
      rows: rows,
      colCount: colCount,
      tableWidth: tableWidth,
      probeCellSize: tableCellFontMaximum(slideWidth),
      font: font,
    ),
  );
  final minCell = tableCellFontMinimum(slideWidth);
  final cellSize = tableFitCellSize(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    availH: availH,
    baseCellSize: math.max(maxCell, minCell),
    minCellSize: minCell,
    font: font,
  );
  final blockHeight = tableBlockHeight(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    cellSize: cellSize,
    font: font,
  );
  return (
    cellSize: cellSize,
    extraVPad: tableExtraRowPadding(
      blockHeight: blockHeight,
      availH: availH,
      rowCount: rows.length,
      cellSize: cellSize,
    ),
  );
}
