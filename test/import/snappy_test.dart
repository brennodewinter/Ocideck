import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/snappy.dart';

/// A raw Snappy block compressing [text] as a single literal.
List<int> _literalBlock(String text) {
  final data = utf8.encode(text);
  final block = <int>[];
  // Leading varint = uncompressed length.
  block.add(data.length);
  // Literal tag: ((len-1) << 2) | 0, then the bytes.
  block.add(((data.length - 1) << 2) & 0xff);
  block.addAll(data);
  return block;
}

/// A raw Snappy block for "abcabc": literal "abc" + a 2-byte copy (len 3, off 3).
final List<int> _copyBlock = [
  0x06, // uncompressed length 6
  0x08, // literal, len-1 = 2 -> len 3
  0x61, 0x62, 0x63, // 'a','b','c'
  0x0A, // copy 2-byte: (tag>>2)+1 = 3 -> len 3
  0x03, 0x00, // offset 3 (LE)
];

List<int> _stream(List<List<int>> chunks, {bool withStreamId = true}) {
  final out = <int>[];
  if (withStreamId) {
    out.addAll([
      0xff, 0x06, 0x00, 0x00, // stream identifier, length 6
      0x73, 0x4e, 0x61, 0x50, 0x70, 0x59, // "sNaPpY"
    ]);
  }
  for (final block in chunks) {
    out.add(0x00); // data chunk type (iWork: no CRC)
    out.add(block.length & 0xff);
    out.add((block.length >> 8) & 0xff);
    out.add((block.length >> 16) & 0xff);
    out.addAll(block);
  }
  return out;
}

void main() {
  final dec = SnappyDecompressor();

  test('decodes a raw literal block', () {
    final out = dec.decodeSnappyRawBlock(_literalBlock('Hello'));
    expect(String.fromCharCodes(out), 'Hello');
  });

  test('decodes a block with a back-copy (overlap-safe)', () {
    final out = dec.decodeSnappyRawBlock(_copyBlock);
    expect(String.fromCharCodes(out), 'abcabc');
  });

  test('decompresses a single-chunk IWA framing stream', () {
    final out = dec.decompressIwaStream(_stream([_literalBlock('Hello')]));
    expect(String.fromCharCodes(out), 'Hello');
  });

  test('concatenates multiple framed chunks', () {
    final out = dec.decompressIwaStream(
      _stream([_literalBlock('foo'), _literalBlock('bar')]),
    );
    expect(String.fromCharCodes(out), 'foobar');
  });

  test('decompresses iWork .iwa without stream identifier', () {
    final out = dec.decompressIwaStream(
      _stream([_literalBlock('Hello')], withStreamId: false),
    );
    expect(String.fromCharCodes(out), 'Hello');
  });

  test('throws FormatException on non-Snappy input', () {
    expect(
      () => dec.decompressIwaStream([0x69, 0x77, 0x61]),
      throwsFormatException,
    );
  });
}
