import 'dart:typed_data';

import 'proto_wire.dart';

/// Parses the decompressed IWA byte stream into individual iWork objects.
///
/// Per the reverse-engineered iWork format (obriensp/iWorkFileFormat,
/// Andrew Sampson's "Reverse Engineering iWork"), the decompressed `.iwa`
/// content is **not** a single protobuf message — it is a stream of records:
///
/// ```
/// while not at end:
///   varint archiveInfoLength
///   bytes  archiveInfo      // a TSP.ArchiveInfo protobuf
///   bytes  payload...       // one per MessageInfo, each `length` long
/// ```
///
/// `TSP.ArchiveInfo`:
/// - field 1 (`uint64`): the object's unique `identifier`.
/// - field 2 (repeated `TSP.MessageInfo`): describes the payload(s) that follow.
///
/// `TSP.MessageInfo`:
/// - field 1 (`uint32`): `type` — numeric id mapped to a schema class via
///   Apple's `TSPRegistry` (not shipped; we keep the id).
/// - field 3 (`uint32`): `length` — the following payload's byte length.
/// - field 5 (packed `uint64`): `object_references` — the object ids that the
///   payload's `TSP.Reference` fields point to, **in order of appearance**. A
///   `TSP.Reference` in the payload stores an index into this list, not the id.
/// - field 6 (packed `uint64`): `data_references` — same idea for data blobs.
///
/// In practice each `ArchiveInfo` carries one `MessageInfo`, so one payload.
class IwaArchive {
  IwaArchive(this._wire);

  final ProtoWire _wire;

  /// Parse [stream] (the full decompressed `.iwa` bytes) into a map of
  /// object identifier → [IwaObject]. Malformed trailing bytes are skipped
  /// rather than throwing, so a partial parse still yields what it could.
  Map<int, IwaObject> parse(List<int> stream) {
    final objects = <int, IwaObject>{};
    var p = 0;
    while (p < stream.length) {
      try {
        final (infoLen, pInfo) = _readVarint(stream, p);
        p = pInfo;
        if (infoLen <= 0 || p + infoLen > stream.length) break;
        final info = _wire.decode(stream.sublist(p, p + infoLen));
        p += infoLen;
        final identifier = info.varint(1);
        if (identifier == null) break;
        final payload = BytesBuilder();
        var objectRefs = <int>[];
        var dataRefs = <int>[];
        final fieldObjectRefs = <int, List<int>>{};
        final fieldDataRefs = <int, List<int>>{};
        for (final mi in info.messages(2)) {
          final length = mi.varint(3);
          if (length == null) break;
          if (p + length > stream.length) break;
          final chunk = Uint8List.fromList(stream.sublist(p, p + length));
          p += length;
          payload.add(chunk);
          final packed5 = _packedVarints(mi.bytes(5));
          final var5 = mi.varints(5);
          objectRefs = [...objectRefs, ...packed5, ...var5];
          dataRefs = [
            ...dataRefs,
            ..._packedVarints(mi.bytes(6)),
            ...mi.varints(6),
          ];
          for (final fi in mi.messages(4)) {
            final path = fi.message(1)?.varints(1);
            final fieldType = fi.varint(2);
            if (path == null || path.isEmpty) continue;
            final field = path.first;
            if (fieldType == 1) {
              // ObjectReference typed field: raw varint indices map to this list.
              final refs = <int>[
                ..._packedVarints(fi.bytes(4)),
                ...fi.varints(4),
              ];
              if (refs.isNotEmpty) {
                (fieldObjectRefs[field] ??= []).addAll(refs);
              }
            } else if (fieldType == 2) {
              // DataReference typed field.
              final drefs = <int>[
                ..._packedVarints(fi.bytes(5)),
                ...fi.varints(5),
              ];
              if (drefs.isNotEmpty) {
                (fieldDataRefs[field] ??= []).addAll(drefs);
              }
            }
          }
        }
        if (payload.isEmpty) continue;
        objects.putIfAbsent(
          identifier,
          () => IwaObject(
            id: identifier,
            typeId: info.messages(2).firstOrNull?.varint(1) ?? 0,
            data: payload.toBytes(),
            objectReferences: objectRefs.toSet().toList(),
            dataReferences: dataRefs.toSet().toList(),
            fieldObjectReferences: fieldObjectRefs,
            fieldDataReferences: fieldDataRefs,
          ),
        );
      } on FormatException {
        break;
      }
    }
    return objects;
  }

  /// Decode a packed `repeated uint64` field (length-delimited varints).
  List<int> _packedVarints(Uint8List? bytes) {
    if (bytes == null) return const [];
    final out = <int>[];
    try {
      var p = 0;
      while (p < bytes.length) {
        final (v, np) = _readVarint(bytes, p);
        out.add(v);
        p = np;
      }
    } on FormatException {
      // Truncated packed list — keep what we have.
    }
    return out;
  }

  (int, int) _readVarint(List<int> b, int start) {
    var result = 0;
    var shift = 0;
    var p = start;
    while (true) {
      if (p >= b.length) {
        throw const FormatException('Truncated IWA varint.');
      }
      final byte = b[p++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (result, p);
  }
}

/// One decoded iWork object: its [id], the numeric protobuf schema [typeId],
/// the raw [data] bytes, and the [objectReferences]/[dataReferences] lists
/// from its `MessageInfo` (used to resolve `TSP.Reference` fields in [data]).
class IwaObject {
  const IwaObject({
    required this.id,
    required this.typeId,
    required this.data,
    this.objectReferences = const [],
    this.dataReferences = const [],
    this.fieldObjectReferences = const {},
    this.fieldDataReferences = const {},
  });

  final int id;
  final int typeId;
  final Uint8List data;
  final List<int> objectReferences;
  final List<int> dataReferences;

  /// Field-level object references decoded from `TSP.FieldInfo`.
  /// Keys are top-level field numbers; values are the ordered object ids for
  /// `ObjectReference` typed fields (raw varints in the payload).
  final Map<int, List<int>> fieldObjectReferences;

  /// Field-level data references decoded from `TSP.FieldInfo`.
  final Map<int, List<int>> fieldDataReferences;

  /// Decode this object's payload as a generic [ProtoMessage].
  ProtoMessage get message => ProtoWire().decode(data);
}
