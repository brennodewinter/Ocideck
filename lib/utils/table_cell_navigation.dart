/// Advancing the cell cursor with Tab/Shift+Tab, shared by the table editor
/// and the live-edit presenter so the two never drift on what "next cell"
/// means — the same lesson as `slideTypeMeta.bulletColumns`: one rule, two
/// oppervlakken.
library;

/// Where Tab from cell (row, col) lands, or `null` when it sits on the last
/// cell of the grid — the caller's signal to append a row and focus its first
/// cell.
({int row, int col})? nextTableCell(
  int row,
  int col,
  int rowCount,
  int colCount,
) {
  var r = row;
  var c = col + 1;
  if (c >= colCount) {
    c = 0;
    r += 1;
  }
  if (r >= rowCount) return null;
  return (row: r, col: c);
}

/// Where Shift+Tab from cell (row, col) lands, or `null` at the first cell —
/// the caller's signal to stay put (no wrapping).
({int row, int col})? prevTableCell(int row, int col, int colCount) {
  var r = row;
  var c = col - 1;
  if (c < 0) {
    if (r == 0) return null;
    r -= 1;
    c = colCount - 1;
  }
  return (row: r, col: c);
}
