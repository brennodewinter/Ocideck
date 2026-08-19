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

/// De pijltjestoets die in een cel is ingedrukt.
enum TableArrow { left, right, up, down }

/// Waar de cursor komt te staan in de cel waar je binnenkomt.
enum TableCaret {
  /// De hele celinhoud geselecteerd — doortypen vervangt. Zo komt een rekenblad
  /// een cel binnen, en zo doen Tab en Enter het hier al.
  selectAll,

  /// Aan het begin van de tekst: je kwam van links.
  start,

  /// Aan het eind van de tekst: je kwam van rechts.
  end,
}

/// Wat een pijltjestoets in een cel te betekenen heeft.
enum TableArrowMove {
  /// De cursor beweegt bínnen de cel; het tekstveld handelt de toets zelf af.
  inCell,

  /// De cursor springt naar een buurcel.
  toCell,

  /// De tabel houdt hier op: de toets doet niets, en mag ook nergens anders
  /// heen. Zie [tableArrowTarget] voor waarom dat verschil telt.
  atEdge,
}

/// Wat een pijltjestoets vanuit cel ([row], [col]) doet.
///
/// De regel is die van een rekenblad, en hij komt voort uit wat een mens
/// verwacht: ←/→ verplaatsen eerst de cursor door de tekst, en pas wanneer die
/// al aan de rand van de celinhoud staat springen ze naar de buurcel. ↑/↓ gaan
/// een rij op of neer, maar niet voordat de cursor de bovenste respectievelijk
/// onderste regel van de cel heeft bereikt — een cel met drie regels tekst laat
/// je er eerst doorheen lopen.
///
/// Geen doorloop voorbij de rand van de tabel: → op de laatste kolom blijft
/// staan waar hij staat. Wie een rij verder wil, gebruikt Tab (die groeit de
/// tabel ook), en wie eruit wil, klikt of tabt eruit. Zonder die grens zou een
/// pijltje je ongemerkt uit de tabel de lopende tekst in schieten.
///
/// Dat [TableArrowMove.atEdge] een eigen uitkomst is en niet "niets te doen",
/// is geen finesse maar de kern van #1565: de cel staat in de visuele editor
/// binnen een Quill-embed. Een toets die de cel niet opeet, loopt door naar
/// Quill, dat er de cursor van het *document* mee verzet terwijl de tekstinvoer
/// nog aan de cel hangt — waarna de hele documenttekst in de cel belandde en de
/// visuele stand op brontekst terugviel. Aan de rand van de tabel moet de toets
/// dus opgegeten worden, niet doorgelaten.
({TableArrowMove move, int row, int col, TableCaret caret}) tableArrowTarget({
  required TableArrow arrow,
  required int row,
  required int col,
  required int rowCount,
  required int colCount,
  required bool atTextStart,
  required bool atTextEnd,
  required bool onFirstLine,
  required bool onLastLine,
}) {
  ({TableArrowMove move, int row, int col, TableCaret caret}) inCell() => (
    move: TableArrowMove.inCell,
    row: row,
    col: col,
    caret: TableCaret.selectAll,
  );
  ({TableArrowMove move, int row, int col, TableCaret caret}) atEdge() => (
    move: TableArrowMove.atEdge,
    row: row,
    col: col,
    caret: TableCaret.selectAll,
  );
  ({TableArrowMove move, int row, int col, TableCaret caret}) to(
    int r,
    int c,
    TableCaret caret,
  ) => (move: TableArrowMove.toCell, row: r, col: c, caret: caret);

  return switch (arrow) {
    TableArrow.left when !atTextStart => inCell(),
    TableArrow.left => col > 0 ? to(row, col - 1, TableCaret.end) : atEdge(),
    TableArrow.right when !atTextEnd => inCell(),
    TableArrow.right =>
      col + 1 < colCount ? to(row, col + 1, TableCaret.start) : atEdge(),
    TableArrow.up when !onFirstLine => inCell(),
    TableArrow.up =>
      row > 0 ? to(row - 1, col, TableCaret.selectAll) : atEdge(),
    TableArrow.down when !onLastLine => inCell(),
    TableArrow.down =>
      row + 1 < rowCount ? to(row + 1, col, TableCaret.selectAll) : atEdge(),
  };
}
