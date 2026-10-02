/// A zip writer for tests, with a knob for every way a zip can lie. The package's
/// own writer (`buildFormPackage`) only ever writes honest zips; the reader's job is
/// the dishonest ones, so the tests need to be able to write them.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

List<int> u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> u32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

class RawEntry {
  RawEntry(
    this.name,
    this.data, {
    this.method = 8,
    this.claimedSize,
    this.crc,
    this.flags = 0,
    this.madeBy = 20,
    this.externalAttributes = 0,
    this.localName,
    this.rawCompressed,
  });

  final String name;
  final List<int> data;

  /// 0 stored, 8 deflate; anything else is written as is (and unreadable).
  final int method;

  /// What the headers say the size is, when it is not the truth.
  final int? claimedSize;
  final int? crc;
  final int flags;
  final int madeBy;
  final int externalAttributes;

  /// The name in the local header, when it differs from the central one.
  final String? localName;

  /// The compressed bytes to write, instead of compressing [data].
  final List<int>? rawCompressed;

  List<int> get compressed =>
      rawCompressed ?? (method == 8 ? deflateRaw(data) : List<int>.from(data));
}

Uint8List deflateRaw(List<int> data) =>
    Uint8List.fromList(Deflate(data).getBytes());

/// A local header with its data, honest, stored.
List<int> storedLocal(String name, List<int> data) => [
  ...u32(0x04034b50),
  ...u16(20),
  ...u16(0),
  ...u16(0),
  ...u16(0),
  ...u16(33),
  ...u32(getCrc32(data)),
  ...u32(data.length),
  ...u32(data.length),
  ...u16(name.length),
  ...u16(0),
  ...name.codeUnits,
  ...data,
];

/// A central directory record for a stored entry whose local header is at
/// [localOffset].
List<int> storedCentral(String name, List<int> data, int localOffset) => [
  ...u32(0x02014b50),
  ...u16(20),
  ...u16(20),
  ...u16(0),
  ...u16(0),
  ...u16(0),
  ...u16(33),
  ...u32(getCrc32(data)),
  ...u32(data.length),
  ...u32(data.length),
  ...u16(name.length),
  ...u16(0),
  ...u16(0),
  ...u16(0),
  ...u16(0),
  ...u32(0),
  ...u32(localOffset),
  ...name.codeUnits,
];

List<int> endRecord(
  int count,
  int cdSize,
  int cdOffset, {
  bool zip64 = false,
  int disk = 0,
  List<int> comment = const [],
}) => [
  ...u32(0x06054b50),
  ...u16(disk),
  ...u16(0),
  ...u16(zip64 ? 0xFFFF : count),
  ...u16(zip64 ? 0xFFFF : count),
  ...u32(cdSize),
  ...u32(zip64 ? 0xFFFFFFFF : cdOffset),
  ...u16(comment.length),
  ...comment,
];

/// Writes [entries] as a zip. [zip64], [disk] and [declaredEntries] tamper with
/// the end record.
Uint8List rawZip(
  List<RawEntry> entries, {
  bool zip64 = false,
  int disk = 0,
  int? declaredEntries,
  List<int> comment = const [],
}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  for (final e in entries) {
    final compressed = e.compressed;
    final crc = e.crc ?? getCrc32(e.data);
    final size = e.claimedSize ?? e.data.length;
    final localOffset = out.length;
    final local = (e.localName ?? e.name).codeUnits;
    out
      ..add(u32(0x04034b50))
      ..add(u16(20))
      ..add(u16(e.flags))
      ..add(u16(e.method))
      ..add(u16(0))
      ..add(u16(33))
      ..add(u32(crc))
      ..add(u32(compressed.length))
      ..add(u32(size))
      ..add(u16(local.length))
      ..add(u16(0))
      ..add(local)
      ..add(compressed);
    central
      ..add(u32(0x02014b50))
      ..add(u16(e.madeBy))
      ..add(u16(20))
      ..add(u16(e.flags))
      ..add(u16(e.method))
      ..add(u16(0))
      ..add(u16(33))
      ..add(u32(crc))
      ..add(u32(compressed.length))
      ..add(u32(size))
      ..add(u16(e.name.length))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u32(e.externalAttributes))
      ..add(u32(localOffset))
      ..add(e.name.codeUnits);
  }
  final cdOffset = out.length;
  final directory = central.toBytes();
  out
    ..add(directory)
    ..add(
      endRecord(
        declaredEntries ?? entries.length,
        directory.length,
        cdOffset,
        zip64: zip64,
        disk: disk,
        comment: comment,
      ),
    );
  return out.toBytes();
}
