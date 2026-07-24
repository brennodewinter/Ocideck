import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_archive.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

int _key(int field, int wireType) => (field << 3) | wireType;

List<int> _varintField(int field, int value) => [
  _key(field, 0),
  ..._varint(value),
];

/// Build one IWA record: [varint infoLen][ArchiveInfo: id + MessageInfo(type,length)][payload].
List<int> _record(int id, int type, List<int> payload) {
  final messageInfo = [
    ..._varintField(1, type),
    ..._varintField(3, payload.length),
  ];
  final archiveInfo = [
    ..._varintField(1, id),
    _key(2, 2),
    ..._varint(messageInfo.length),
    ...messageInfo,
  ];
  return [..._varint(archiveInfo.length), ...archiveInfo, ...payload];
}

/// Like [_record] but the MessageInfo carries `object_references` (field 5,
/// packed uint64) — the ids the payload's TSP.Reference fields point to.
List<int> _recordWithRefs(
  int id,
  int type,
  List<int> payload,
  List<int> objectRefs,
) {
  final packed = <int>[];
  for (final r in objectRefs) {
    packed.addAll(_varint(r));
  }
  final messageInfo = [
    ..._varintField(1, type),
    ..._varintField(3, payload.length),
    _key(5, 2), // packed repeated uint64
    ..._varint(packed.length),
    ...packed,
  ];
  final archiveInfo = [
    ..._varintField(1, id),
    _key(2, 2),
    ..._varint(messageInfo.length),
    ...messageInfo,
  ];
  return [..._varint(archiveInfo.length), ...archiveInfo, ...payload];
}

void main() {
  final wire = ProtoWire();

  test('parses a single object with its id, type and payload', () {
    final stream = _record(42, 7, [0x08, 0x01]); // payload: {field1=1}
    final objects = IwaArchive(wire).parse(stream);
    expect(objects, contains(42));
    final obj = objects[42]!;
    expect(obj.typeId, 7);
    expect(obj.id, 42);
    expect(obj.message.varint(1), 1);
  });

  test('parses multiple consecutive objects', () {
    final stream = [
      ..._record(1, 10, [0x08, 0x01]),
      ..._record(2, 20, [0x08, 0x02]),
    ];
    final objects = IwaArchive(wire).parse(stream);
    expect(objects.keys, [1, 2]);
    expect(objects[1]!.typeId, 10);
    expect(objects[2]!.typeId, 20);
  });

  test('keeps the first payload per identifier (should_merge ignored)', () {
    final stream = [
      ..._record(9, 1, [0x08, 0x01]),
      ..._record(9, 2, [0x08, 0x02]),
    ];
    final objects = IwaArchive(wire).parse(stream);
    expect(objects, hasLength(1));
    expect(objects[9]!.typeId, 1);
  });

  test('tolerates truncated trailing bytes', () {
    final stream = [
      ..._record(1, 1, [0x08, 0x01]),
      0xff,
    ]; // dangling varint
    final objects = IwaArchive(wire).parse(stream);
    expect(objects, contains(1));
  });

  test('returns empty for an empty stream', () {
    expect(IwaArchive(wire).parse(<int>[]), isEmpty);
  });

  test('captures object_references from MessageInfo field 5', () {
    final stream = _recordWithRefs(7, 1, [0x08, 0x00], [100, 200]);
    final objects = IwaArchive(wire).parse(stream);
    expect(objects[7]!.objectReferences, [100, 200]);
  });
}
