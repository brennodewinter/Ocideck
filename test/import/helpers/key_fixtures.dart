// Shared IWA / Snappy / zip fixture builders for Keynote importer tests.
//
// Lets both the unit-level key_importer_test and the end-to-end pipeline test
// build synthetic `.key` archives from schema-conformant IWA object graphs
// without duplicating the low-level wire-format plumbing.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const xmlPlist =
    '<?xml version="1.0"?>'
    '<plist version="1.0"><dict>'
    '<key>title</key><string>Q3 Roadmap</string>'
    '<key>authors</key><array><string>Jane Doe</string></array>'
    '</dict></plist>';

List<int> b(String s) => Uint8List.fromList(utf8.encode(s));

List<int> zip(Map<String, Object> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = content is List<int>
        ? Uint8List.fromList(content)
        : Uint8List.fromList((content as String).codeUnits);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return ZipEncoder().encode(archive);
}

// --- protobuf wire helpers --------------------------------------------------

List<int> varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

int key(int field, int wireType) => (field << 3) | wireType;

List<int> varintField(int field, int value) => [
  ...varint(key(field, 0)),
  ...varint(value),
];

/// A length-delimited string field.
List<int> stringField(int field, String text) {
  final data = utf8.encode(text);
  return [...varint(key(field, 2)), ...varint(data.length), ...data];
}

/// A protobuf payload with one UTF-8 string field (field 1).
List<int> stringPayload(String text) => stringField(1, text);

/// A ShapeInfoArchive payload: empty ShapeArchive super (field 1) + a
/// containedStorage reference (field 2, index into object_references).
List<int> shapeInfoPayload(int storageRefIndex) => [
  ...varint(key(1, 2)),
  ...varint(0),
  ...varintField(2, storageRefIndex),
];

/// A StorageArchive payload: repeated `text` string field 3.
List<int> storagePayload(List<String> texts) => [
  for (final t in texts) ...[
    ...varint(key(3, 2)),
    ...varint(utf8.encode(t).length),
    ...utf8.encode(t),
  ],
];

/// A ParagraphStyleArchive payload (typeId 2022) with a `listLevel` (field 10).
List<int> paragraphStylePayload(int listLevel) => varintField(10, listLevel);

/// A StorageArchive payload with text (field 3) and a paragraph-style map
/// (field 5) that assigns a [styleRefIndex] per paragraph. [text] is a single
/// string with `\n`-separated paragraphs; [styleRefIndices] has one entry per
/// paragraph. Entries with a `null` style inherit the previous paragraph's
/// style. [styleRefIndex]es are indices into the StorageArchive's
/// `object_references` list.
List<int> storagePayloadWithLevels(String text, List<int?> styleRefIndices) {
  final out = storagePayload([text]);
  // Build the paragraph-style map: field 5 → submessage → field 1 (repeated).
  final lines = text.split('\n');
  var offset = 0;
  final entries = <List<int>>[];
  for (var i = 0; i < styleRefIndices.length; i++) {
    final entry = <int>[...varintField(1, offset)];
    final refIdx = styleRefIndices[i];
    if (refIdx != null) {
      final styleRef = varintField(1, refIdx);
      entry.addAll(bytesField(2, styleRef));
    }
    entries.add(entry);
    offset += utf8.encode(lines[i]).length + 1; // +1 for the newline
  }
  final paraMap = <int>[];
  for (final e in entries) {
    paraMap.addAll(bytesField(1, e));
  }
  out.addAll(bytesField(5, paraMap));
  return out;
}

/// A SlideArchive payload: title ref (5), body ref (6), optional drawables (7),
/// optional note ref (27).
List<int> slidePayload({
  required int titleRefIndex,
  required int bodyRefIndex,
  int? noteRefIndex,
  List<int> drawableRefIndices = const [],
}) {
  final out = <int>[
    ...varintField(5, titleRefIndex),
    ...varintField(6, bodyRefIndex),
  ];
  if (noteRefIndex != null) out.addAll(varintField(27, noteRefIndex));
  for (final d in drawableRefIndices) {
    out.addAll(varintField(7, d));
  }
  return out;
}

/// A NoteArchive payload: `containedStorage` (field 1, Reference).
List<int> notePayload(int storageRefIndex) => varintField(1, storageRefIndex);

/// A SlideTreeArchive payload: repeated field 2 with SlideNode reference
/// submessages. Each [nodeRefIndex] is an index into the enclosing object's
/// `object_references` list.
List<int> slideTreePayload(List<int> nodeRefIndices) => [
  for (final idx in nodeRefIndices) ...bytesField(2, varintField(1, idx)),
];

/// A SlideNodeArchive payload: `children` (field 1, repeated Reference) and/or
/// `slide` (field 2, single Reference). Each value is an index into the node's
/// object_references.
List<int> slideNodePayload({
  int? slideRefIndex,
  List<int> childrenRefIndices = const [],
}) {
  final out = <int>[];
  for (final c in childrenRefIndices) {
    out.addAll(varintField(1, c));
  }
  if (slideRefIndex != null) out.addAll(varintField(2, slideRefIndex));
  return out;
}

/// An ImageArchive payload: empty DrawableArchive super (field 1) + a
/// `TSP.DataReference` in `data` (field 11) pointing at [dataId].
List<int> imagePayload(int dataId) {
  final dataReference = varintField(1, dataId);
  return [
    ...varint(key(1, 2)),
    ...varint(0), // empty DrawableArchive super
    ...varint(key(11, 2)),
    ...varint(dataReference.length),
    ...dataReference,
  ];
}

/// A length-delimited bytes field.
List<int> bytesField(int field, List<int> value) => [
  ...varint(key(field, 2)),
  ...varint(value.length),
  ...value,
];

/// A fixed-64 (wire type 1) double field.
List<int> doubleField(int field, double value) => [
  ...varint(key(field, 1)),
  ..._doubleLE(value),
];

/// A ChartDrawableArchive payload: empty DrawableArchive super (field 1) and
/// the TSCH.ChartArchive extension (field 10000, length-delimited).
List<int> chartDrawablePayload(List<int> chartArchive) => [
  ...varint(key(1, 2)),
  ...varint(0), // empty TSD.DrawableArchive super
  ...bytesField(10000, chartArchive),
];

/// A ChartArchive payload with the chart type, series direction and embedded
/// ChartGridArchive (field 7).
List<int> chartArchivePayload({
  required int chartType,
  List<int>? chartGrid,
  int seriesDirection = 1, // by row
  int? scatterFormat,
  int? mediatorRefIndex,
}) {
  final out = <int>[...varintField(1, chartType)];
  if (chartGrid != null) {
    out.addAll(bytesField(7, chartGrid));
  }
  if (scatterFormat != null) {
    out.addAll(varintField(2, scatterFormat));
  }
  out.addAll(varintField(5, seriesDirection));
  if (mediatorRefIndex != null) {
    out.addAll(varintField(8, mediatorRefIndex));
  }
  return out;
}

/// A ChartMediatorArchive payload: a reference (field 1) to a ChartInfoArchive.
List<int> chartMediatorPayload(int infoRefIndex) =>
    varintField(1, infoRefIndex);

/// A ChartInfoArchive payload: a reference (field 1) to a ChartGridArchive.
List<int> chartInfoPayload(int gridRefIndex) => varintField(1, gridRefIndex);

/// A ChartGridArchive payload with row/column names and grid rows.
List<int> chartGridPayload({
  List<String> rowNames = const [],
  List<String> columnNames = const [],
  List<List<int>> gridRows = const [],
}) {
  final out = <int>[
    for (final name in rowNames) ...stringField(1, name),
    for (final name in columnNames) ...stringField(2, name),
  ];
  for (final row in gridRows) {
    out.addAll(varint(key(3, 2)));
    out.addAll(varint(row.length));
    out.addAll(row);
  }
  return out;
}

/// A GridRow payload containing GridValue submessages.
List<int> gridRowPayload(List<List<int>> gridValues) {
  final out = <int>[];
  for (final value in gridValues) {
    out.addAll(varint(key(1, 2)));
    out.addAll(varint(value.length));
    out.addAll(value);
  }
  return out;
}

/// A GridValue payload with a numeric or date value.
List<int> gridValuePayload(double value, {bool isDate = false}) =>
    doubleField(isDate ? 2 : 1, value);

/// A TSP.DataReference payload: identifier (1).
List<int> dataReferencePayload(int dataId) => varintField(1, dataId);

/// A GroupArchive payload: empty DrawableArchive super (field 1) and
/// repeated child references (field 2).
List<int> groupPayload({List<int> childRefIndices = const []}) => [
  ...varint(key(1, 2)),
  ...varint(0), // empty TSD.DrawableArchive super
  for (final idx in childRefIndices) ...varintField(2, idx),
];

/// A MovieArchive payload: empty DrawableArchive super (field 1) and optional
/// movieData (14), importedAuxiliaryMovieData (22), movieRemoteURL (17),
/// posterImageData (15) and audioOnly (9).
List<int> moviePayload({
  int? movieDataId,
  int? auxiliaryDataId,
  String? movieRemoteURL,
  int? posterImageDataId,
  bool audioOnly = false,
}) {
  final out = <int>[
    ...varint(key(1, 2)),
    ...varint(0), // empty TSD.DrawableArchive super
  ];
  if (movieDataId != null) {
    out.addAll(bytesField(14, dataReferencePayload(movieDataId)));
  }
  if (auxiliaryDataId != null) {
    out.addAll(bytesField(22, dataReferencePayload(auxiliaryDataId)));
  }
  if (movieRemoteURL != null && movieRemoteURL.isNotEmpty) {
    out.addAll(stringField(17, movieRemoteURL));
  }
  if (posterImageDataId != null) {
    out.addAll(bytesField(15, dataReferencePayload(posterImageDataId)));
  }
  if (audioOnly) {
    out.addAll(varintField(9, 1));
  }
  return out;
}

/// A DataInfo payload: identifier (1), digest (2), preferred_file_name (3).
List<int> dataInfoPayload({
  required int identifier,
  String preferredFileName = '',
  String? fileName,
}) {
  final out = <int>[
    ...varintField(1, identifier),
    ...bytesField(2, const []),
    ...stringField(3, preferredFileName),
  ];
  if (fileName != null) {
    out.addAll(stringField(4, fileName));
  }
  return out;
}

/// A TableInfoArchive payload: empty DrawableArchive super (field 1) and a
/// `tableModel` reference (field 2, index into object_references).
List<int> tableInfoPayload(int tableModelRefIndex) => [
  ...varint(key(1, 2)),
  ...varint(0), // empty TSD.DrawableArchive super
  ...varintField(2, tableModelRefIndex),
];

/// A TableModelArchive payload with the given [dataStore] submessage and
/// dimensions. The first row is treated as the header.
List<int> tableModelPayload({
  required List<int> dataStore,
  int numberOfRows = 2,
  int numberOfColumns = 3,
  int numberOfHeaderRows = 1,
  int numberOfHeaderColumns = 0,
  int numberOfFooterRows = 0,
}) {
  final out = <int>[
    ...stringField(1, 'table1'),
    ...bytesField(4, dataStore),
    ...varintField(6, numberOfRows),
    ...varintField(7, numberOfColumns),
    ...varintField(9, numberOfHeaderRows),
  ];
  if (numberOfHeaderColumns > 0) {
    out.addAll(varintField(10, numberOfHeaderColumns));
  }
  if (numberOfFooterRows > 0) {
    out.addAll(varintField(11, numberOfFooterRows));
  }
  return out;
}

/// A DataStore payload: embedded TileStorage (field 3), a string-table
/// reference (field 4), an optional rich-text table reference (field 17) and
/// an optional row-to-tile tree descriptor (field 9).
List<int> dataStorePayload({
  required List<int> tileStorage,
  required int stringTableRefIndex,
  int? richTextTableRefIndex,
  List<int>? rowTileTree,
  bool mergedCells = false,
}) {
  final out = <int>[
    ...bytesField(3, tileStorage),
    ...varintField(4, stringTableRefIndex),
  ];
  if (richTextTableRefIndex != null) {
    out.addAll(varintField(17, richTextTableRefIndex));
  }
  if (rowTileTree != null) {
    out.addAll(bytesField(9, rowTileTree));
  }
  if (mergedCells) {
    out.addAll(varintField(13, 1));
  }
  return out;
}

/// A TreeDescriptor payload with nodes that map a start row to a tile index.
List<int> rowTileTreePayload({
  List<(int startRow, int tileArrayIndex)> nodes = const [],
}) {
  final out = <int>[];
  for (final n in nodes) {
    final node = [...varintField(1, n.$1), ...varintField(2, n.$2)];
    out.addAll(varint(key(1, 2)));
    out.addAll(varint(node.length));
    out.addAll(node);
  }
  return out;
}

/// A TileStorage payload with a single tile reference.
List<int> tileStoragePayload({required int tileId, required int tileRefIndex}) {
  final entry = [...varintField(1, tileId), ...varintField(2, tileRefIndex)];
  return [...varint(key(1, 2)), ...varint(entry.length), ...entry];
}

/// A Tile payload with `maxColumn`, `maxRow`, `numCells`, `numrows` and the
/// given `rowInfo` submessages.
List<int> tilePayload({
  required int maxColumn,
  required int maxRow,
  required int numCells,
  required int numRows,
  List<List<int>> rowInfos = const [],
}) {
  final out = <int>[
    ...varintField(1, maxColumn),
    ...varintField(2, maxRow),
    ...varintField(3, numCells),
    ...varintField(4, numRows),
  ];
  for (final ri in rowInfos) {
    out.addAll(varint(key(5, 2)));
    out.addAll(varint(ri.length));
    out.addAll(ri);
  }
  return out;
}

/// A TileRowInfo payload: `tileRowIndex`, `cellCount`, `cellStorageBuffer` and
/// `cellOffsets`.
List<int> tileRowInfoPayload(int tileRowIndex, List<List<int>> cellBuffers) {
  final offsets = <int>[];
  final storage = <int>[];
  var offset = 0;
  for (final cell in cellBuffers) {
    offsets.addAll(_uint16LE(offset));
    storage.addAll(cell);
    offset += cell.length;
  }

  return [
    ...varintField(1, tileRowIndex),
    ...varintField(2, cellBuffers.length),
    ...bytesField(3, storage),
    ...bytesField(4, offsets),
  ];
}

/// A TableDataList payload with `listType` (1) and `ListEntry` submessages.
List<int> tableDataListPayload({
  required int listType,
  required List<(int key, String value)> entries,
}) {
  final out = <int>[...varintField(1, listType), ...varintField(2, 1)];
  for (final e in entries) {
    final entry = [
      ...varintField(1, e.$1),
      ...varintField(2, 1),
      ...stringField(3, e.$2),
    ];
    out.addAll(varint(key(3, 2)));
    out.addAll(varint(entry.length));
    out.addAll(entry);
  }
  return out;
}

/// A TableDataList payload for rich-text entries. Each entry carries a `key`
/// (1) and a `ref` (4) pointing at the index in the list's `object_references`.
List<int> richTextListPayload({
  required int listType,
  required List<(int key, int refIdx)> entries,
}) {
  final out = <int>[...varintField(1, listType), ...varintField(2, 1)];
  for (final e in entries) {
    final entry = [
      ...varintField(1, e.$1),
      ...varintField(2, 1),
      ...varintField(4, e.$2),
    ];
    out.addAll(varint(key(3, 2)));
    out.addAll(varint(entry.length));
    out.addAll(entry);
  }
  return out;
}

/// A V5 cell storage buffer for a single cell. Supported values:
/// - stringIndex (type 3)
/// - doubleValue (type 2)
/// - dateTimeValue (type 5)
/// - errorIndex (type 8)
/// - richTextIndex (type 9)
/// - decimalValue (type 2 with decimal placeholder)
List<int> v5Cell({
  required int type,
  int? stringIndex,
  double? doubleValue,
  double? dateTimeValue,
  int? errorIndex,
  int? richTextIndex,
  List<int>? decimalValue,
}) {
  final fields = <(int mask, int size, List<int> bytes)>[];
  if (decimalValue != null) {
    fields.add((0x000001, 16, decimalValue));
  }
  if (doubleValue != null) {
    fields.add((0x000002, 8, _doubleLE(doubleValue)));
  }
  if (dateTimeValue != null) {
    fields.add((0x000004, 8, _doubleLE(dateTimeValue)));
  }
  if (stringIndex != null) {
    fields.add((0x000008, 4, _uint32LE(stringIndex)));
  }
  if (richTextIndex != null) {
    fields.add((0x000010, 4, _uint32LE(richTextIndex)));
  }
  if (errorIndex != null) {
    fields.add((0x000800, 4, _uint32LE(errorIndex)));
  }

  var mask = 0;
  final fieldBytes = <int>[];
  for (final (m, _, bytes) in fields) {
    mask |= m;
    fieldBytes.addAll(bytes);
  }

  final out = BytesBuilder();
  out.addByte(5); // version
  out.addByte(type);
  out.add([0, 0, 0, 0, 0, 0]); // bytes 2-7
  out.add(_uint32LE(mask)); // mask at offset 8
  out.add(fieldBytes);
  return out.toBytes();
}

/// A V3/V4 (or V0/V2) cell storage buffer. V3/V4 differ only in the cell type
/// position; V0/V2 use the same layout as V3.
List<int> v3Cell({
  required int type,
  int? stringIndex,
  double? doubleValue,
  double? dateTimeValue,
  int? errorIndex,
  int? richTextIndex,
}) => _oldCell(
  version: 3,
  cellTypeOffset: 2,
  type: type,
  stringIndex: stringIndex,
  doubleValue: doubleValue,
  dateTimeValue: dateTimeValue,
  errorIndex: errorIndex,
  richTextIndex: richTextIndex,
);

List<int> v4Cell({
  required int type,
  int? stringIndex,
  double? doubleValue,
  double? dateTimeValue,
  int? errorIndex,
  int? richTextIndex,
}) => _oldCell(
  version: 4,
  cellTypeOffset: 1,
  type: type,
  stringIndex: stringIndex,
  doubleValue: doubleValue,
  dateTimeValue: dateTimeValue,
  errorIndex: errorIndex,
  richTextIndex: richTextIndex,
);

List<int> _oldCell({
  required int version,
  required int cellTypeOffset,
  required int type,
  int? stringIndex,
  double? doubleValue,
  double? dateTimeValue,
  int? errorIndex,
  int? richTextIndex,
}) {
  var mask = 0;
  final fieldBytes = BytesBuilder();
  if (errorIndex != null) {
    mask |= 0x000100;
    fieldBytes.add(_uint32LE(errorIndex));
  }
  if (richTextIndex != null) {
    mask |= 0x000200;
    fieldBytes.add(_uint32LE(richTextIndex));
  }
  if (stringIndex != null) {
    mask |= 0x000010;
    fieldBytes.add(_uint32LE(stringIndex));
  }
  if (doubleValue != null) {
    mask |= 0x000020;
    fieldBytes.add(_doubleLE(doubleValue));
  }
  if (dateTimeValue != null) {
    mask |= 0x000040;
    fieldBytes.add(_doubleLE(dateTimeValue));
  }

  final out = BytesBuilder();
  out.addByte(version);
  for (var i = 1; i < cellTypeOffset; i++) {
    out.addByte(0);
  }
  out.addByte(type);
  for (var i = cellTypeOffset + 1; i < 4; i++) {
    out.addByte(0);
  }
  out.add(_uint32LE(mask)); // mask at offset 4
  for (var i = 8; i < 12; i++) {
    out.addByte(0);
  }
  out.add(fieldBytes.toBytes());
  return out.toBytes();
}

List<int> _uint16LE(int v) => [v & 0xff, (v >> 8) & 0xff];

List<int> _uint32LE(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

List<int> _doubleLE(double v) {
  final b = ByteData(8)..setFloat64(0, v, Endian.little);
  return b.buffer.asUint8List().toList();
}

/// A PackageMetadata payload: `datas` (field 4) containing DataInfo submessages,
/// and optionally `components` (field 3) with ComponentMetadata submessages.
List<int> packageMetadataPayload({
  List<List<int>> dataInfos = const [],
  List<({int objectId, String locator})> components = const [],
}) {
  final out = <int>[
    ...varintField(1, 100), // last_object_identifier
  ];
  for (final comp in components) {
    // ComponentMetadata: field 1 = TSP.Reference submessage (wire type 2),
    // field 3 = locator string.
    final refPayload = varintField(1, comp.objectId);
    final compPayload = [
      ...bytesField(1, refPayload), // TSP.Reference as submessage
      ...bytesField(3, comp.locator.codeUnits), // locator string
    ];
    out.addAll(varint(key(3, 2)));
    out.addAll(varint(compPayload.length));
    out.addAll(compPayload);
  }
  for (final di in dataInfos) {
    out.addAll(varint(key(4, 2)));
    out.addAll(varint(di.length));
    out.addAll(di);
  }
  return out;
}

// --- IWA framing ------------------------------------------------------------

/// One IWA record: [varint infoLen][ArchiveInfo{id, MessageInfo(type,len)}][payload].
List<int> record(int id, int type, List<int> payload) {
  final messageInfo = [
    ...varintField(1, type),
    ...varintField(3, payload.length),
  ];
  final archiveInfo = [
    ...varintField(1, id),
    key(2, 2),
    ...varint(messageInfo.length),
    ...messageInfo,
  ];
  return [...varint(archiveInfo.length), ...archiveInfo, ...payload];
}

/// Like [record] but the MessageInfo carries `object_references` (field 5,
/// packed uint64) — the ids the payload's TSP.Reference fields point to.
List<int> recordWithRefs(
  int id,
  int type,
  List<int> payload,
  List<int> objectRefs,
) {
  final packed = <int>[];
  for (final r in objectRefs) {
    packed.addAll(varint(r));
  }
  final messageInfo = [
    ...varintField(1, type),
    ...varintField(3, payload.length),
    key(5, 2),
    ...varint(packed.length),
    ...packed,
  ];
  final archiveInfo = [
    ...varintField(1, id),
    key(2, 2),
    ...varint(messageInfo.length),
    ...messageInfo,
  ];
  return [...varint(archiveInfo.length), ...archiveInfo, ...payload];
}

/// A raw Snappy block (varint len + literal) wrapping [bytes], supporting the
/// extended literal length encoding for blocks > 61 bytes.
List<int> snappyBlock(List<int> bytes) {
  final l = bytes.length - 1; // literal stores length-1
  final header = <int>[];
  if (l < 60) {
    header.add((l << 2) & 0xff);
  } else {
    final n = l <= 0xff ? 1 : (l <= 0xffff ? 2 : (l <= 0xffffff ? 3 : 4));
    header.add(((60 + (n - 1)) << 2) & 0xff);
    for (var i = 0; i < n; i++) {
      header.add((l >> (8 * i)) & 0xff);
    }
  }
  final block = <int>[...varint(bytes.length), ...header];
  block.addAll(bytes);
  return block;
}

/// A full Snappy-framed IWA stream: stream identifier chunk + one 0x00 data
/// chunk carrying [recordBytes] compressed as a single Snappy raw block.
List<int> iwaStream(List<int> recordBytes) {
  final block = snappyBlock(recordBytes);
  return <int>[
    0xff, 0x06, 0x00, 0x00, 0x73, 0x4e, 0x61, 0x50, 0x70, 0x59, // sNaPpY
    0x00, // data chunk type
    block.length & 0xff,
    (block.length >> 8) & 0xff,
    (block.length >> 16) & 0xff,
    ...block,
  ];
}
