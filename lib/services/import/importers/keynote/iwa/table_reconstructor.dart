import '../../../models/conversion_issue.dart';
import '../../../models/source_table.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'proto_wire.dart';
import 'table_cell_reader.dart';
import 'table_data.dart';

/// Reconstructs a [SourceTable] from a `TST.TableInfoArchive` drawable.
///
/// Walks `TableInfoArchive -> TableModelArchive -> DataStore -> TileStorage ->
/// Tile -> TileRowInfo -> cell storage` to recover the cell grid. It handles
/// single-tile tables (the common case for Keynote slides) and records
/// unsupported layouts as [ConversionIssue]s.
class TableReconstructor {
  TableReconstructor(this.doc);

  final IwaDocument doc;

  final List<ConversionIssue> issues = [];

  /// Reconstruct the table referenced by [tableDrawable] (a `TableInfoArchive`).
  ///
  /// [slideIndex] is used for the [ConversionIssue.slideIndex] field.
  SourceTable? reconstruct(IwaObject tableDrawable, int slideIndex) {
    issues.clear();
    final tableModelRef = tableDrawable.message.varint(2);
    if (tableModelRef == null) return null;
    final tableModel = doc.resolveReference(tableDrawable, tableModelRef);
    if (tableModel == null) return null;

    final rowCount = tableModel.message.varint(6) ?? 0;
    final colCount = tableModel.message.varint(7) ?? 0;
    if (rowCount == 0 || colCount == 0) return null;

    final headerRows = tableModel.message.varint(9) ?? 0;
    final headerColumns = tableModel.message.varint(10) ?? 0;
    final footerRows = tableModel.message.varint(11) ?? 0;

    final dataStore = tableModel.message.message(4);
    if (dataStore == null) return null;

    final tableData = TableData.read(doc, tableModel);
    final reader = TableCellReader(tableData);

    final rowInfos = _collectRowInfos(tableModel, dataStore, rowCount);
    if (rowInfos.isEmpty) return null;

    final grid = <List<String>>[];
    for (var r = 0; r < rowCount; r++) {
      final row = List<String>.filled(colCount, '');
      final rowInfo = rowInfos[r];
      if (rowInfo != null) {
        final cells = reader.readRow(rowInfo);
        for (var c = 0; c < colCount; c++) {
          if (c < cells.length) row[c] = cells[c];
        }
      }
      grid.add(row);
    }

    _recordLayoutIssues(
      slideIndex,
      dataStore,
      headerRows: headerRows,
      headerColumns: headerColumns,
      footerRows: footerRows,
    );

    final header = grid.first;
    final rows = grid.length > 1 ? grid.sublist(1) : <List<String>>[];
    return SourceTable(header: header, rows: rows);
  }

  /// Build a map from global row index to the `TileRowInfo` that contains it.
  Map<int, ProtoMessage> _collectRowInfos(
    IwaObject tableModel,
    ProtoMessage dataStore,
    int rowCount,
  ) {
    final out = <int, ProtoMessage>{};
    final tileStorage = dataStore.message(3);
    if (tileStorage == null) return out;

    final tileEntries = tileStorage.messages(1);
    final rowTileTree = dataStore.message(9);
    final nodes = rowTileTree?.messages(1) ?? const [];

    for (final node in nodes) {
      final startRow = node.varint(1) ?? 0;
      final tileArrayIndex = node.varint(2) ?? 0;
      final tileEntry = tileArrayIndex < tileEntries.length
          ? tileEntries[tileArrayIndex]
          : _tileEntryById(tileEntries, tileArrayIndex);
      if (tileEntry == null) continue;

      final tileRef = tileEntry.varint(2);
      if (tileRef == null) continue;
      final tile = doc.resolveReference(tableModel, tileRef);
      if (tile == null) continue;

      for (final rowInfo in tile.message.messages(5)) {
        final tileRowIndex = rowInfo.varint(1) ?? 0;
        final globalRow = startRow + tileRowIndex;
        if (globalRow < rowCount) {
          out[globalRow] = rowInfo;
        }
      }
    }

    // Fallback: if the tree is empty or invalid, treat the first tile as
    // containing all rows. This is a robustness net for synthetic fixtures.
    if (out.isEmpty && tileEntries.isNotEmpty) {
      final first = tileEntries.first;
      final tileRef = first.varint(2);
      if (tileRef != null) {
        final tile = doc.resolveReference(tableModel, tileRef);
        if (tile != null) {
          for (final rowInfo in tile.message.messages(5)) {
            final tileRowIndex = rowInfo.varint(1) ?? 0;
            if (tileRowIndex < rowCount) {
              out[tileRowIndex] = rowInfo;
            }
          }
        }
      }
    }

    return out;
  }

  ProtoMessage? _tileEntryById(List<ProtoMessage> entries, int id) {
    for (final e in entries) {
      if (e.varint(1) == id) return e;
    }
    return null;
  }

  void _recordLayoutIssues(
    int slideIndex,
    ProtoMessage dataStore, {
    required int headerRows,
    required int headerColumns,
    required int footerRows,
  }) {
    if (headerRows > 1) {
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Keynote tabel header',
          description:
              'Meerdere headerrijen worden in Markdown niet ondersteund; '
              'alleen de eerste rij wordt als tabelheader gebruikt.',
          salvagedAs: 'eerste rij als header',
        ),
      );
    }
    if (headerColumns > 0) {
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Keynote tabel headerkolommen',
          description: 'Headerkolommen worden in OciDeck niet ondersteund.',
        ),
      );
    }
    if (footerRows > 0) {
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Keynote tabel footer',
          description: 'Footerrijen worden in Markdown niet ondersteund.',
        ),
      );
    }
    if (dataStore.varint(13) != null) {
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Samengevoegde cellen',
          description:
              'Samengevoegde tabelcellen worden in GFM-tabellen niet '
              'ondersteund; de tabel is platgeklapt.',
        ),
      );
    }
  }
}
