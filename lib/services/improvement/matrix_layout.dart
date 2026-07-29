// De matrix-engine: van [MatrixSpec] naar een [Scene] (PROCESS_IMPROVEMENT §7).
//
// Eén layoutberekening, twee achterkanten. De app tekent de scene met
// `ScenePainter`, de HTML-export serialiseert dezelfde scene met `sceneToSvg`.
// Dat is hier geen netheid maar de les uit `_maxY`, dat woordelijk gedupliceerd
// stond tussen de schilder en de SVG-serialiser en dus twee keer moest worden
// gerepareerd — met één testsuite per kopie als enige verband.
//
// Puur Dart. Tekst meten gaat via [TextMeasurer], zodat dezelfde maten in beide
// werelden uitkomen.
library;

import '../scene/scene.dart';
import 'matrix_spec.dart';

/// De kleuren die de matrix gebruikt, als hex. Meegegeven in plaats van
/// opgehaald: deze laag mag geen Flutter-thema kennen.
class MatrixPalette {
  const MatrixPalette({
    this.ink = '#0F172A',
    this.muted = '#64748B',
    this.rule = '#CBD5E1',
    this.headerFill = '#E2E8F0',
    this.zebraFill = '#F8FAFC',
    this.accent = '#003399',
    this.alarm = '#B91C1C',
  });

  final String ink;
  final String muted;
  final String rule;
  final String headerFill;
  final String zebraFill;
  final String accent;

  /// Voor een afgeleide waarde die om aandacht vraagt (een hoge RPN).
  final String alarm;
}

/// Boven welke RPN een rij als "hier zit het" wordt aangezet.
///
/// 100 is de gangbare drempel in FMEA-praktijk en bewust gewoon rekenwerk: geen
/// AIAG-VDA-actietabel, die is auteursrechtelijk beschermd (§18).
const int kMatrixRpnAlarmThreshold = 100;

/// De layoutmaten van de matrix. Alles in scene-eenheden.
class _Metrics {
  const _Metrics({
    required this.fontSize,
    required this.headerFontSize,
    required this.lineHeight,
    required this.cellPadX,
    required this.cellPadY,
  });

  final double fontSize;
  final double headerFontSize;
  final double lineHeight;
  final double cellPadX;
  final double cellPadY;
}

/// Bouwt de scene voor één matrix.
///
/// [rows] zijn de gegevensrijen in weergaveorde (zie `matrixDisplayRows`);
/// [displayColumns] mag afgeleide kolommen bevatten — die worden berekend uit
/// [spec], niet uit de rij.
Scene buildMatrixScene({
  required MatrixSpec spec,
  required List<MatrixColumn> displayColumns,
  required List<List<String>> rows,
  required TextMeasurer measurer,
  String title = '',
  String languageCode = 'nl',
  MatrixPalette palette = const MatrixPalette(),
  double width = 960,
  double height = 540,
}) {
  final nodes = <SceneNode>[];
  const margin = 40.0;
  var top = margin;

  if (title.trim().isNotEmpty) {
    const titleSize = 30.0;
    nodes.add(
      SceneText(
        x: margin,
        y: top + titleSize,
        text: title.trim(),
        fontSize: titleSize,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    top += titleSize * 1.6;
  }

  final guidance = improvementTemplateById(
    spec.templateId,
  )?.guidance(languageCode);
  if (guidance != null && guidance.isNotEmpty) {
    const noteSize = 15.0;
    nodes.add(
      SceneText(
        x: margin,
        y: top + noteSize,
        text: guidance,
        fontSize: noteSize,
        fill: palette.muted,
      ),
    );
    top += noteSize * 1.9;
  }

  final gridWidth = width - margin * 2;
  final available = height - margin - top;
  final table = _fitTable(
    columns: displayColumns,
    rows: rows,
    spec: spec,
    measurer: measurer,
    languageCode: languageCode,
    gridWidth: gridWidth,
    available: available,
  );
  nodes.addAll(
    _tableNodes(
      table: table,
      palette: palette,
      x: margin,
      y: top,
      gridWidth: gridWidth,
    ),
  );
  return Scene(width: width, height: height, nodes: nodes);
}

/// Een uitgerekende tabel: kolombreedtes, per rij de gewikkelde cellen en de
/// hoogte, plus de maten waarmee dat is gemeten.
class _Table {
  _Table({
    required this.columnWidths,
    required this.header,
    required this.body,
    required this.rowHeights,
    required this.headerHeight,
    required this.metrics,
    required this.alarmRows,
  });

  final List<double> columnWidths;
  final List<List<String>> header;
  final List<List<List<String>>> body;
  final List<double> rowHeights;
  final double headerHeight;
  final _Metrics metrics;

  /// De rijen (index in [body]) waarvan de afgeleide waarde de drempel haalt.
  final Set<int> alarmRows;
}

/// Zoekt de grootste lettergrootte waarop de tabel nog in [available] past.
///
/// Aflopend in plaats van een formule: de hoogte hangt van het *wikkelen* af, en
/// dat is niet omkeerbaar — een halve punt kleiner kan een kolom een regel
/// schelen en daarmee de hele tabel. Vandaar meten, niet rekenen. De ondergrens
/// is de laatste kandidaat: liever een tabel die net te hoog is dan tekst die
/// niemand op een beamer nog leest.
_Table _fitTable({
  required List<MatrixColumn> columns,
  required List<List<String>> rows,
  required MatrixSpec spec,
  required TextMeasurer measurer,
  required String languageCode,
  required double gridWidth,
  required double available,
}) {
  const candidates = [18.0, 16.0, 14.0, 12.5, 11.0, 10.0, 9.0];
  _Table? last;
  for (final size in candidates) {
    final table = _measureTable(
      columns: columns,
      rows: rows,
      spec: spec,
      measurer: measurer,
      languageCode: languageCode,
      gridWidth: gridWidth,
      metrics: _Metrics(
        fontSize: size,
        headerFontSize: size,
        lineHeight: measurer.lineHeight(fontSize: size),
        cellPadX: 8,
        cellPadY: 6,
      ),
    );
    last = table;
    final total =
        table.headerHeight + table.rowHeights.fold<double>(0, (a, b) => a + b);
    if (total <= available) return table;
  }
  return last!;
}

_Table _measureTable({
  required List<MatrixColumn> columns,
  required List<List<String>> rows,
  required MatrixSpec spec,
  required TextMeasurer measurer,
  required String languageCode,
  required double gridWidth,
  required _Metrics metrics,
}) {
  final cells = <List<String>>[];
  final alarmRows = <int>{};
  for (var r = 0; r < rows.length; r++) {
    final row = <String>[];
    for (final column in columns) {
      row.add(_cellText(column, rows[r], spec));
    }
    cells.add(row);
    final rpn = MatrixSpec.derivedRpn(rows[r], spec.columns);
    if (rpn != null && rpn >= kMatrixRpnAlarmThreshold) alarmRows.add(r);
  }

  final widths = _columnWidths(
    columns: columns,
    cells: cells,
    measurer: measurer,
    languageCode: languageCode,
    metrics: metrics,
    gridWidth: gridWidth,
  );

  List<List<String>> wrap(List<String> row) => [
    for (var c = 0; c < row.length; c++)
      _wrapText(
        row[c],
        maxWidth: widths[c] - metrics.cellPadX * 2,
        fontSize: metrics.fontSize,
        measurer: measurer,
      ),
  ];

  final header = wrap([
    for (final column in columns) _columnLabel(column, languageCode),
  ]);
  final body = [for (final row in cells) wrap(row)];
  double heightOf(List<List<String>> wrapped) {
    final lines = wrapped.fold<int>(
      1,
      (m, cell) => cell.length > m ? cell.length : m,
    );
    return lines * metrics.lineHeight + metrics.cellPadY * 2;
  }

  return _Table(
    columnWidths: widths,
    header: header,
    body: body,
    rowHeights: [for (final row in body) heightOf(row)],
    headerHeight: heightOf(header),
    metrics: metrics,
    alarmRows: alarmRows,
  );
}

/// De tekst in één cel: de opgeslagen waarde, of de berekende bij een afgeleide
/// kolom. Een afgeleide waarde die niet te berekenen valt blijft leeg — een 0
/// zou een uitspraak zijn die de gegevens niet doen.
String _cellText(MatrixColumn column, List<String> row, MatrixSpec spec) {
  if (!column.derived) {
    final i = spec.columns.indexWhere((c) => c.key == column.key);
    return i < 0 || i >= row.length ? '' : row[i].trim();
  }
  if (column.key != 'rpn') return '';
  final rpn = MatrixSpec.derivedRpn(row, spec.columns);
  return rpn?.toString() ?? '';
}

String _columnLabel(MatrixColumn column, String languageCode) =>
    languageCode.startsWith('nl') ? column.labelNl : column.labelEn;

/// Kolombreedtes: elke kolom krijgt naar rato van haar breedste inhoud, met een
/// bodem zodat een smalle kolom (`S`, `O`, `D`) niet tot niets krimpt, en een
/// plafond zodat één lange cel de rest niet wegdrukt.
List<double> _columnWidths({
  required List<MatrixColumn> columns,
  required List<List<String>> cells,
  required TextMeasurer measurer,
  required String languageCode,
  required _Metrics metrics,
  required double gridWidth,
}) {
  final minWidth = metrics.fontSize * 2.4 + metrics.cellPadX * 2;
  final maxWidth = gridWidth * 0.32;
  final desired = <double>[];
  for (var c = 0; c < columns.length; c++) {
    var widest = measurer.widthOf(
      _columnLabel(columns[c], languageCode),
      fontSize: metrics.headerFontSize,
    );
    for (final row in cells) {
      if (c >= row.length) continue;
      final w = measurer.widthOf(row[c], fontSize: metrics.fontSize);
      if (w > widest) widest = w;
    }
    final padded = widest + metrics.cellPadX * 2;
    desired.add(padded.clamp(minWidth, maxWidth));
  }
  final total = desired.fold<double>(0, (a, b) => a + b);
  if (total <= 0) {
    return List<double>.filled(columns.length, gridWidth / columns.length);
  }
  final scale = gridWidth / total;
  return [for (final w in desired) w * scale];
}

/// Breekt [text] op woorden binnen [maxWidth]. Een woord dat zelf te lang is
/// blijft heel: liever een cel die uitloopt dan een afgekapt kenmerk waarvan
/// niemand ziet dat er iets is weggevallen.
List<String> _wrapText(
  String text, {
  required double maxWidth,
  required double fontSize,
  required TextMeasurer measurer,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [''];
  if (maxWidth <= 0) return [trimmed];
  final lines = <String>[];
  var current = '';
  for (final word in trimmed.split(RegExp(r'\s+'))) {
    final candidate = current.isEmpty ? word : '$current $word';
    if (measurer.widthOf(candidate, fontSize: fontSize) <= maxWidth ||
        current.isEmpty) {
      current = candidate;
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

/// Zet de uitgerekende tabel om in scene-knopen: vlakken, lijnen, tekst.
List<SceneNode> _tableNodes({
  required _Table table,
  required MatrixPalette palette,
  required double x,
  required double y,
  required double gridWidth,
}) {
  final nodes = <SceneNode>[];
  final m = table.metrics;

  void cells(
    List<List<String>> wrapped,
    double rowY,
    double rowHeight, {
    required bool header,
    required bool alarm,
  }) {
    var cellX = x;
    for (var c = 0; c < wrapped.length; c++) {
      final columnWidth = table.columnWidths[c];
      final derived = alarm && c == wrapped.length - 1;
      for (var line = 0; line < wrapped[c].length; line++) {
        nodes.add(
          SceneText(
            x: cellX + m.cellPadX,
            y: rowY + m.cellPadY + (line + 1) * m.lineHeight,
            text: wrapped[c][line],
            fontSize: header ? m.headerFontSize : m.fontSize,
            fill: header
                ? palette.ink
                : (derived ? palette.alarm : palette.ink),
            fontWeight: header || derived ? 700 : 400,
          ),
        );
      }
      cellX += columnWidth;
    }
  }

  nodes.add(
    SceneRect(
      x: x,
      y: y,
      width: gridWidth,
      height: table.headerHeight,
      fill: palette.headerFill,
    ),
  );
  cells(table.header, y, table.headerHeight, header: true, alarm: false);

  var rowY = y + table.headerHeight;
  for (var r = 0; r < table.body.length; r++) {
    final rowHeight = table.rowHeights[r];
    if (r.isOdd) {
      nodes.add(
        SceneRect(
          x: x,
          y: rowY,
          width: gridWidth,
          height: rowHeight,
          fill: palette.zebraFill,
        ),
      );
    }
    cells(
      table.body[r],
      rowY,
      rowHeight,
      header: false,
      alarm: table.alarmRows.contains(r),
    );
    nodes.add(
      SceneLine(
        x1: x,
        y1: rowY,
        x2: x + gridWidth,
        y2: rowY,
        stroke: palette.rule,
      ),
    );
    rowY += rowHeight;
  }
  nodes.add(
    SceneLine(
      x1: x,
      y1: rowY,
      x2: x + gridWidth,
      y2: rowY,
      stroke: palette.rule,
    ),
  );

  var lineX = x;
  for (final columnWidth in table.columnWidths) {
    nodes.add(
      SceneLine(x1: lineX, y1: y, x2: lineX, y2: rowY, stroke: palette.rule),
    );
    lineX += columnWidth;
  }
  nodes.add(
    SceneLine(
      x1: x + gridWidth,
      y1: y,
      x2: x + gridWidth,
      y2: rowY,
      stroke: palette.rule,
    ),
  );
  return nodes;
}
