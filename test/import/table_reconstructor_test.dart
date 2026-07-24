import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_archive.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_document.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/snappy.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/table_data.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/table_reconstructor.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  final wire = ProtoWire();
  final archive = IwaArchive(wire);
  final snappy = SnappyDecompressor();

  IwaDocument buildDoc(List<int> recordBytes) {
    final stream = fx.iwaStream(recordBytes);
    final objects = archive.parse(snappy.decompressIwaStream(stream));
    return IwaDocument(objects);
  }

  test('reconstructs a simple 2x3 table from V5 cells', () {
    // String table object (id 10).
    final stringTable = fx.record(
      10,
      100,
      fx.tableDataListPayload(
        listType: 1,
        entries: [
          (0, 'Name'),
          (1, 'Age'),
          (2, 'City'),
          (3, 'Alice'),
          (4, '30'),
          (5, 'Rotterdam'),
        ],
      ),
    );

    // Tile object (id 12) with two rows of cells.
    final row0 = fx.tileRowInfoPayload(0, [
      fx.v5Cell(type: 3, stringIndex: 0),
      fx.v5Cell(type: 3, stringIndex: 1),
      fx.v5Cell(type: 3, stringIndex: 2),
    ]);
    final row1 = fx.tileRowInfoPayload(1, [
      fx.v5Cell(type: 3, stringIndex: 3),
      fx.v5Cell(type: 3, stringIndex: 4),
      fx.v5Cell(type: 3, stringIndex: 5),
    ]);
    final tile = fx.record(
      12,
      6002,
      fx.tilePayload(
        maxColumn: 2,
        maxRow: 1,
        numCells: 6,
        numRows: 2,
        rowInfos: [row0, row1],
      ),
    );

    // DataStore (embedded) references string table (ref 0) and tile (ref 1).
    final dataStore = fx.dataStorePayload(
      tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 1),
      stringTableRefIndex: 0,
    );

    // Table model (id 11) references string table (10) and tile (12).
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: dataStore,
        numberOfRows: 2,
        numberOfColumns: 3,
        numberOfHeaderRows: 1,
      ),
      [10, 12],
    );

    // TableInfoArchive (id 13) references the table model.
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);

    final doc = buildDoc([
      ...stringTable,
      ...tile,
      ...tableModel,
      ...tableInfo,
    ]);
    final tableDrawable = doc[13]!;
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(tableDrawable, 0);

    expect(table, isNotNull);
    expect(table!.header, ['Name', 'Age', 'City']);
    expect(table.rows, [
      ['Alice', '30', 'Rotterdam'],
    ]);
    expect(reconstructor.issues, isEmpty);
  });

  test('records an issue when header rows are not exactly one', () {
    final stringTable = fx.record(
      10,
      100,
      fx.tableDataListPayload(
        listType: 1,
        entries: [(0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')],
      ),
    );
    final row0 = fx.tileRowInfoPayload(0, [
      fx.v5Cell(type: 3, stringIndex: 0),
      fx.v5Cell(type: 3, stringIndex: 1),
    ]);
    final row1 = fx.tileRowInfoPayload(1, [
      fx.v5Cell(type: 3, stringIndex: 2),
      fx.v5Cell(type: 3, stringIndex: 3),
    ]);
    final tile = fx.record(
      12,
      6002,
      fx.tilePayload(
        maxColumn: 1,
        maxRow: 1,
        numCells: 4,
        numRows: 2,
        rowInfos: [row0, row1],
      ),
    );
    final dataStore = fx.dataStorePayload(
      tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 1),
      stringTableRefIndex: 0,
    );
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: dataStore,
        numberOfRows: 2,
        numberOfColumns: 2,
        numberOfHeaderRows: 2, // unsupported: more than one header row
      ),
      [10, 12],
    );
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);

    final doc = buildDoc([
      ...stringTable,
      ...tile,
      ...tableModel,
      ...tableInfo,
    ]);
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(doc[13]!, 0);

    expect(table, isNotNull);
    expect(table!.header, ['A', 'B']);
    expect(table.rows, [
      ['C', 'D'],
    ]);
    expect(reconstructor.issues, isNotEmpty);
    expect(
      reconstructor.issues.any((i) => i.feature.contains('header')),
      isTrue,
    );
  });

  test('records header columns, footer rows and merged cells as issues', () {
    final stringTable = fx.record(
      10,
      100,
      fx.tableDataListPayload(
        listType: 1,
        entries: [(0, 'A'), (1, 'B'), (2, 'C')],
      ),
    );
    final row0 = fx.tileRowInfoPayload(0, [
      fx.v5Cell(type: 3, stringIndex: 0),
      fx.v5Cell(type: 3, stringIndex: 1),
    ]);
    final row1 = fx.tileRowInfoPayload(1, [
      fx.v5Cell(type: 3, stringIndex: 2),
      fx.v5Cell(type: 3, stringIndex: 2),
    ]);
    final tile = fx.record(
      12,
      6002,
      fx.tilePayload(
        maxColumn: 1,
        maxRow: 1,
        numCells: 4,
        numRows: 2,
        rowInfos: [row0, row1],
      ),
    );
    final dataStore = fx.dataStorePayload(
      tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 1),
      stringTableRefIndex: 0,
      mergedCells: true,
    );
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: dataStore,
        numberOfRows: 2,
        numberOfColumns: 2,
        numberOfHeaderRows: 1,
        numberOfHeaderColumns: 1,
        numberOfFooterRows: 1,
      ),
      [10, 12],
    );
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);

    final doc = buildDoc([
      ...stringTable,
      ...tile,
      ...tableModel,
      ...tableInfo,
    ]);
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(doc[13]!, 0);

    expect(table, isNotNull);
    expect(reconstructor.issues, hasLength(3));
    expect(
      reconstructor.issues.map((i) => i.feature).toSet(),
      containsAll([
        'Keynote tabel headerkolommen',
        'Keynote tabel footer',
        'Samengevoegde cellen',
      ]),
    );
  });

  test('returns null when row or column count is zero', () {
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: fx.dataStorePayload(
          tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 0),
          stringTableRefIndex: 0,
        ),
        numberOfRows: 0,
        numberOfColumns: 2,
      ),
      [10],
    );
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);
    final doc = buildDoc([...tableModel, ...tableInfo]);
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(doc[13]!, 0);
    expect(table, isNull);
  });

  test('returns null when there is no DataStore', () {
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: const <int>[],
        numberOfRows: 2,
        numberOfColumns: 2,
      ),
      [],
    );
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);
    final doc = buildDoc([...tableModel, ...tableInfo]);
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(doc[13]!, 0);
    expect(table, isNull);
  });

  test('fills missing row infos with empty cells', () {
    final stringTable = fx.record(
      10,
      100,
      fx.tableDataListPayload(listType: 1, entries: [(0, 'A'), (1, 'B')]),
    );
    // Only the first row is present in the tile.
    final row0 = fx.tileRowInfoPayload(0, [
      fx.v5Cell(type: 3, stringIndex: 0),
      fx.v5Cell(type: 3, stringIndex: 1),
    ]);
    final tile = fx.record(
      12,
      6002,
      fx.tilePayload(
        maxColumn: 1,
        maxRow: 0,
        numCells: 2,
        numRows: 1,
        rowInfos: [row0],
      ),
    );
    final dataStore = fx.dataStorePayload(
      tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 1),
      stringTableRefIndex: 0,
    );
    final tableModel = fx.recordWithRefs(
      11,
      6001,
      fx.tableModelPayload(
        dataStore: dataStore,
        numberOfRows: 3,
        numberOfColumns: 2,
        numberOfHeaderRows: 1,
      ),
      [10, 12],
    );
    final tableInfo = fx.recordWithRefs(13, 6000, fx.tableInfoPayload(0), [11]);

    final doc = buildDoc([
      ...stringTable,
      ...tile,
      ...tableModel,
      ...tableInfo,
    ]);
    final reconstructor = TableReconstructor(doc);
    final table = reconstructor.reconstruct(doc[13]!, 0);

    expect(table, isNotNull);
    expect(table!.header, ['A', 'B']);
    expect(table.rows, hasLength(2));
    expect(table.rows[0], ['', '']);
    expect(table.rows[1], ['', '']);
  });

  test('TableData.read builds string, error and rich-text lookups', () {
    final stringList = fx.record(
      10,
      100,
      fx.tableDataListPayload(listType: 1, entries: [(0, 'A'), (1, 'B')]),
    );
    final errorList = fx.record(
      11,
      100,
      fx.tableDataListPayload(listType: 2, entries: [(0, '#ERR')]),
    );
    final storage = fx.record(14, 3, fx.storagePayload(['Rich']));
    final payload = fx.recordWithRefs(13, 100, fx.varintField(1, 0), [14]);
    final richTextList = fx.recordWithRefs(
      12,
      100,
      fx.richTextListPayload(listType: 1, entries: [(0, 0)]),
      [13],
    );

    final dataStore = [
      ...fx.dataStorePayload(
        tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 0),
        stringTableRefIndex: 0,
        richTextTableRefIndex: 1,
      ),
      ...fx.varintField(12, 2), // error list reference
    ];

    final tableModel = fx.recordWithRefs(
      1,
      6001,
      fx.tableModelPayload(
        dataStore: dataStore,
        numberOfRows: 1,
        numberOfColumns: 1,
      ),
      [10, 12, 11],
    );

    final doc = buildDoc(
      [
        stringList,
        errorList,
        richTextList,
        payload,
        storage,
        tableModel,
      ].expand((e) => e).toList(),
    );
    final tableData = TableData.read(doc, doc[1]!);

    expect(tableData.strings, {0: 'A', 1: 'B'});
    expect(tableData.errors, {0: '#ERR'});
    expect(tableData.richTexts, {0: 'Rich'});
  });
}
