import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/table_cell_reader.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/table_data.dart';

import 'helpers/key_fixtures.dart' as fx;

List<int> _uint16LE(int v) => [v & 0xff, (v >> 8) & 0xff];

void main() {
  final wire = ProtoWire();

  ProtoMessage rowInfoFrom(List<List<int>> cells) {
    final bytes = fx.tileRowInfoPayload(0, cells);
    return wire.decode(bytes);
  }

  test('reads V5 string cells', () {
    final data = TableData(strings: {0: 'Hello', 1: 'World'});
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v5Cell(type: 3, stringIndex: 0),
      fx.v5Cell(type: 3, stringIndex: 1),
    ]);
    expect(reader.readRow(row), ['Hello', 'World']);
  });

  test('reads V5 number, boolean, duration and date cells', () {
    final base = DateTime.utc(2001, 1, 1);
    final target = DateTime.utc(2026, 7, 11, 20, 30, 0);
    final seconds = target.difference(base).inSeconds.toDouble();

    final data = TableData(strings: {});
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v5Cell(type: 2, doubleValue: 3.1415),
      fx.v5Cell(type: 6, doubleValue: 1.0), // true
      fx.v5Cell(type: 6, doubleValue: 0.0), // false
      fx.v5Cell(type: 7, doubleValue: 3665.0), // 1h 1m 5s
      fx.v5Cell(type: 5, dateTimeValue: seconds),
    ]);
    final values = reader.readRow(row);
    expect(values[0], '3.1415');
    expect(values[1], 'true');
    expect(values[2], 'false');
    expect(values[3], '1h 1m 5s');
    expect(values[4], '2026-07-11 20:30:00');
  });

  test('reads V5 error, blank and rich text cells', () {
    final data = TableData(
      errors: {0: '#DIV/0!', 1: '#VALUE!'},
      richTexts: {0: 'Rich text'},
    );
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v5Cell(type: 0), // blank
      fx.v5Cell(type: 8, errorIndex: 0),
      fx.v5Cell(type: 9, richTextIndex: 0),
      fx.v5Cell(type: 8, errorIndex: 1),
    ]);
    expect(reader.readRow(row), ['', '#DIV/0!', 'Rich text', '#VALUE!']);
  });

  test('marks decimal cells as unsupported', () {
    final data = TableData();
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v5Cell(type: 2, decimalValue: List<int>.filled(16, 0)),
    ]);
    expect(reader.readRow(row), ['#NUM']);
  });

  test('treats 0xFFFF as an empty missing cell', () {
    final data = TableData(strings: {0: 'A'});
    final reader = TableCellReader(data);
    final firstCell = fx.v5Cell(type: 3, stringIndex: 0);
    final row = wire.decode([
      ...fx.varintField(1, 0),
      ...fx.varintField(2, 2),
      ...fx.bytesField(3, firstCell),
      ...fx.bytesField(4, [..._uint16LE(0), ..._uint16LE(0xFFFF)]),
    ]);
    expect(reader.readRow(row), ['A', '']);
  });

  test('reads V3 string and number cells', () {
    final data = TableData(strings: {0: 'V3', 1: 'cell'});
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v3Cell(type: 3, stringIndex: 0),
      fx.v3Cell(type: 2, doubleValue: 1.5),
      fx.v3Cell(type: 3, stringIndex: 1),
    ]);
    expect(reader.readRow(row), ['V3', '1.5', 'cell']);
  });

  test('reads V4 string and number cells', () {
    final data = TableData(strings: {0: 'V4', 1: 'cell'});
    final reader = TableCellReader(data);
    final row = rowInfoFrom([
      fx.v4Cell(type: 3, stringIndex: 0),
      fx.v4Cell(type: 2, doubleValue: 2.5),
      fx.v4Cell(type: 3, stringIndex: 1),
    ]);
    expect(reader.readRow(row), ['V4', '2.5', 'cell']);
  });

  test('returns empty for an unknown version or malformed offset', () {
    final data = TableData(strings: {0: 'A'});
    final reader = TableCellReader(data);
    final row = wire.decode([
      ...fx.varintField(1, 0),
      ...fx.varintField(2, 2),
      ...fx.bytesField(3, [99]), // unknown version
      ...fx.bytesField(4, [..._uint16LE(0), ..._uint16LE(0)]),
    ]);
    expect(reader.readRow(row), ['', '']);
  });

  test('returns empty row when rowInfo has no buffer or offsets', () {
    final reader = TableCellReader(TableData(strings: {0: 'A'}));
    final row = wire.decode([...fx.varintField(1, 0), ...fx.varintField(2, 1)]);
    expect(reader.readRow(row), const <String>[]);
  });
}
