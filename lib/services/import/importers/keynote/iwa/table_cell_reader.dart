import 'dart:typed_data';

import 'proto_wire.dart';
import 'table_data.dart';

/// Parses the binary `TileRowInfo.cellStorageBuffer` for a single row.
///
/// iWork stores table cells in a custom binary format (not protobuf). This
/// reader supports V4/V5 cell storage (and the very similar V3 layout), walks
/// the field bitmasks in the documented order, and extracts the values needed
/// for OciDeck Markdown: text, numbers, dates, booleans, durations, errors and
/// rich text. Anything it cannot decode becomes an empty string.
class TableCellReader {
  TableCellReader(this._data);

  final TableData _data;

  /// Decodes the cells described by [rowInfo] into plain strings.
  ///
  /// [rowInfo] is a `TST.TileRowInfo` [ProtoMessage] with fields
  /// `cellCount` (2), `cellStorageBuffer` (3) and `cellOffsets` (4).
  List<String> readRow(ProtoMessage rowInfo) {
    final buffer = rowInfo.bytes(3);
    final offsets = rowInfo.bytes(4);
    final count = rowInfo.varint(2) ?? 0;
    if (buffer == null || offsets == null || count == 0) return const [];

    final out = <String>[];
    final offsetView = ByteData.sublistView(offsets);
    for (var i = 0; i < count; i++) {
      final offset = offsetView.getUint16(i * 2, Endian.little);
      if (offset == 0xFFFF) {
        out.add('');
      } else {
        out.add(_readCell(buffer, offset));
      }
    }
    return out;
  }

  String _readCell(Uint8List buffer, int offset) {
    if (offset >= buffer.length) return '';
    final version = buffer[offset];

    // V5 (new / BNC storage)
    if (version == 5) return _readV5(buffer, offset);

    // V4, V3 and V1 are all "old" storage; V1 is not common in Keynote 6+.
    if (version == 4 ||
        version == 3 ||
        version == 2 ||
        version == 1 ||
        version == 0) {
      return _readOld(buffer, offset, version);
    }

    return '';
  }

  String _readOld(Uint8List buffer, int offset, int version) {
    final isV1 = version <= 1;
    final maskSize = isV1 ? 2 : 4;
    final cellTypeOffset = version == 4 ? 1 : 2;
    final fieldsStart = isV1 ? 8 : 12;
    const maskOffset = 4;

    if (offset + cellTypeOffset + 1 > buffer.length) return '';
    final cellType = buffer[offset + cellTypeOffset];

    if (offset + maskOffset + maskSize > buffer.length) return '';
    final mask = _readUintLE(buffer, offset + maskOffset, maskSize);

    final fieldOffsets = <String, int>{};
    var pos = offset + fieldsStart;
    final fieldList = isV1 ? _v1Fields : _v3Fields;
    for (final f in fieldList) {
      if ((mask & f.mask) != 0) {
        fieldOffsets[f.name] = pos;
        pos += f.size;
      }
    }

    return _valueForCellType(cellType, fieldOffsets, buffer);
  }

  String _readV5(Uint8List buffer, int offset) {
    const fieldsStart = 12;
    const maskOffset = 8;

    if (offset + 2 > buffer.length) return '';
    final cellType = buffer[offset + 1];

    if (offset + maskOffset + 4 > buffer.length) return '';
    final mask = _readUintLE(buffer, offset + maskOffset, 4);

    final fieldOffsets = <String, int>{};
    var pos = offset + fieldsStart;
    for (final f in _v5Fields) {
      if ((mask & f.mask) != 0) {
        fieldOffsets[f.name] = pos;
        pos += f.size;
      }
    }

    return _valueForCellType(cellType, fieldOffsets, buffer);
  }

  String _valueForCellType(
    int cellType,
    Map<String, int> offsets,
    Uint8List buffer,
  ) {
    switch (cellType) {
      case 0: // blank
        return '';
      case 2: // number / decimal
        if (offsets['doubleValue'] case final p?) {
          return _readDouble(buffer, p)?.toString() ?? '';
        }
        if (offsets['decimalValue'] != null) {
          // Decimal128 is not representable as a Dart double; leave a marker.
          return '#NUM';
        }
        return '';
      case 3: // string
        final idx = _readUint32(buffer, offsets['stringIndex']);
        if (idx == null) return '';
        return _data.strings[idx] ?? '';
      case 5: // date
        final seconds = _readDouble(buffer, offsets['dateTimeValue']);
        if (seconds == null) return '';
        return _formatDate(seconds);
      case 6: // boolean
        final v = _readDouble(buffer, offsets['doubleValue']);
        return v == null ? '' : (v > 0 ? 'true' : 'false');
      case 7: // duration
        final seconds = _readDouble(buffer, offsets['doubleValue']);
        if (seconds == null) return '';
        return _formatDuration(seconds);
      case 8: // error
        final idx = _readUint32(buffer, offsets['errorIndex']);
        if (idx == null) return '#ERROR';
        return _data.errors[idx] ?? '#ERROR';
      case 9: // rich text
        final idx = _readUint32(buffer, offsets['richTextIndex']);
        if (idx == null) return '';
        return _data.richTexts[idx] ?? '';
    }
    return '';
  }

  double? _readDouble(Uint8List buffer, int? offset) {
    if (offset == null || offset + 8 > buffer.length) return null;
    return ByteData.sublistView(buffer).getFloat64(offset, Endian.little);
  }

  int? _readUint32(Uint8List buffer, int? offset) {
    if (offset == null || offset + 4 > buffer.length) return null;
    return ByteData.sublistView(buffer).getUint32(offset, Endian.little);
  }

  int _readUintLE(Uint8List buffer, int offset, int size) {
    var value = 0;
    for (var i = 0; i < size; i++) {
      value |= buffer[offset + i] << (8 * i);
    }
    return value;
  }

  String _formatDate(double seconds) {
    // iWork date values are seconds since 1 January 2001 UTC.
    final base = DateTime.utc(2001, 1, 1);
    final dt = base.add(Duration(microseconds: (seconds * 1e6).round()));
    // Trim to seconds for clean Markdown.
    return dt.toIso8601String().split('.').first.replaceFirst('T', ' ');
  }

  String _formatDuration(double seconds) {
    var remaining = seconds.abs().round();
    final days = remaining ~/ 86400;
    remaining -= days * 86400;
    final hours = remaining ~/ 3600;
    remaining -= hours * 3600;
    final minutes = remaining ~/ 60;
    remaining -= minutes * 60;
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (remaining > 0 || parts.isEmpty) parts.add('${remaining}s');
    return parts.join(' ');
  }

  static const _v1Fields = [
    _Field('cellStyle', 0x000002, 4),
    _Field('currentFormat', 0x000004, 4),
    _Field('formula', 0x000008, 4),
    _Field('textStyle', 0x000080, 4),
    _Field('errorIndex', 0x000100, 4),
    _Field('richTextIndex', 0x000200, 4),
    _Field('commentStorage', 0x001000, 4),
    _Field('stringIndex', 0x000010, 4),
    _Field('doubleValue', 0x000020, 8),
    _Field('dateTimeValue', 0x000040, 8),
  ];

  static const _v3Fields = [
    _Field('cellStyle', 0x000002, 4),
    _Field('currentFormat', 0x000004, 4),
    _Field('formula', 0x000008, 4),
    _Field('textStyle', 0x000080, 4),
    _Field('conditionalStyle', 0x000400, 4),
    _Field('conditionalStyleApplied', 0x000800, 4),
    _Field('errorIndex', 0x000100, 4),
    _Field('richTextIndex', 0x000200, 4),
    _Field('commentStorage', 0x001000, 4),
    _Field('importWarningSet', 0x002000, 4),
    _Field('stringIndex', 0x000010, 4),
    _Field('doubleValue', 0x000020, 8),
    _Field('dateTimeValue', 0x000040, 8),
  ];

  static const _v5Fields = [
    _Field('decimalValue', 0x000001, 16),
    _Field('doubleValue', 0x000002, 8),
    _Field('dateTimeValue', 0x000004, 8),
    _Field('stringIndex', 0x000008, 4),
    _Field('richTextIndex', 0x000010, 4),
    _Field('cellStyle', 0x000020, 4),
    _Field('textStyle', 0x000040, 4),
    _Field('conditionalStyle', 0x000080, 4),
    _Field('conditionalStyleApplied', 0x000100, 4),
    _Field('formula', 0x000200, 4),
    _Field('controlCellSpec', 0x000400, 4),
    _Field('errorIndex', 0x000800, 4),
    _Field('suggestCellFormat', 0x001000, 4),
    _Field('numberFormat', 0x002000, 4),
    _Field('currencyFormat', 0x004000, 4),
    _Field('dateFormat', 0x008000, 4),
    _Field('durationFormat', 0x010000, 4),
    _Field('textFormat', 0x020000, 4),
    _Field('booleanFormat', 0x040000, 4),
    _Field('commentStorage', 0x080000, 4),
    _Field('importWarningSet', 0x100000, 4),
  ];
}

class _Field {
  const _Field(this.name, this.mask, this.size);
  final String name;
  final int mask;
  final int size;
}
