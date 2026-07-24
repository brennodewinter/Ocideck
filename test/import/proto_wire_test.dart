import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';

/// Encode a varint (LEB128).
List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

/// A field header: (field << 3) | wireType.
int _key(int field, int wireType) => (field << 3) | wireType;

List<int> _varintField(int field, int value) => [
  _key(field, 0),
  ..._varint(value),
];

List<int> _bytesField(int field, List<int> payload) => [
  _key(field, 2),
  ..._varint(payload.length),
  ...payload,
];

void main() {
  final wire = ProtoWire();

  test('decodes a varint field', () {
    // field 1 = 150 (classic protobuf example).
    final msg = wire.decode(_varintField(1, 150));
    expect(msg.varint(1), 150);
  });

  test('decodes a length-delimited string field', () {
    final msg = wire.decode(_bytesField(2, utf8.encode('test')));
    expect(msg.string(2), 'test');
  });

  test('decodes a nested submessage', () {
    final sub = _varintField(1, 7);
    final msg = wire.decode(_bytesField(3, sub));
    final nested = msg.message(3);
    expect(nested, isNotNull);
    expect(nested!.varint(1), 7);
  });

  test('collects repeated varints and messages', () {
    final sub1 = _varintField(1, 1);
    final sub2 = _varintField(1, 2);
    final bytes = [
      ..._varintField(4, 1),
      ..._varintField(4, 2),
      ..._bytesField(5, sub1),
      ..._bytesField(5, sub2),
    ];
    final msg = wire.decode(bytes);
    expect(msg.varints(4), [1, 2]);
    expect(msg.messages(5).map((m) => m.varint(1)).toList(), [1, 2]);
  });

  test('string() returns null for non-UTF-8 bytes', () {
    final msg = wire.decode(_bytesField(9, [0xff, 0xfe, 0xfd]));
    expect(msg.string(9), isNull);
    expect(msg.bytes(9), isNotNull);
  });

  test('fixed32 and fixed64 fields decode little-endian', () {
    final bytes = <int>[
      _key(1, 5), 0x01, 0x00, 0x00, 0x00, // fixed32 = 1
      _key(2, 1), 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // fixed64 = 2
    ];
    final msg = wire.decode(bytes);
    final f32 = msg[1]!.single;
    final f64 = msg[2]!.single;
    expect((f32 as Fixed32Value).value, 1);
    expect((f64 as Fixed64Value).value, 2);
  });

  test('skips deprecated group wire types', () {
    // field 1, wire type 3 (start group) with a matching end-group tag (4),
    // then a normal varint field. The decoder silently skips groups.
    final bytes = [_key(1, 3), _key(1, 4), _key(2, 0), ..._varint(42)];
    final msg = wire.decode(bytes);
    expect(msg.varint(1), isNull);
    expect(msg.varint(2), 42);
  });
}
