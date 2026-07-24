import 'dart:convert';
import 'dart:typed_data';

/// Generic, schema-free Protocol Buffers wire-format decoder.
///
/// iWork's IWA objects are protobuf messages whose `.proto` schemas are not
/// shipped with Keynote. Rather than generate message classes from a
/// hand-reconstructed schema, we decode the raw wire format into a generic
/// [ProtoMessage] (field number → repeated values) and let the IWA layer
/// interpret the fields it cares about. This mirrors how tools like
/// `protoc --decode_raw` work.
///
/// Supported wire types: 0 (varint), 1 (64-bit fixed), 2 (length-delimited),
/// 5 (32-bit fixed). Start/end group wire types (3/4) are unsupported and
/// throw — iWork does not use them.
class ProtoWire {
  /// Decode [data] into a [ProtoMessage].
  ProtoMessage decode(List<int> data) {
    final fields = <int, List<ProtoValue>>{};
    var p = 0;
    while (p < data.length) {
      final (key, pKey) = _readVarint(data, p);
      p = pKey;
      final field = key >> 3;
      final wireType = key & 7;
      final ProtoValue v;
      switch (wireType) {
        case 0:
          final (val, pVal) = _readVarint(data, p);
          p = pVal;
          v = VarintValue(val);
        case 1:
          v = Fixed64Value(_readFixedLE(data, p, 8));
          p += 8;
        case 2:
          final (len, pLen) = _readVarint(data, p);
          p = pLen;
          final end = p + len;
          if (end > data.length) {
            throw const FormatException(
              'Protobuf length-delimited field overruns the buffer.',
            );
          }
          v = BytesValue(Uint8List.fromList(data.sublist(p, end)));
          p = end;
        case 5:
          v = Fixed32Value(_readFixedLE(data, p, 4));
          p += 4;
        case 3: // start group
          // Skip groups (deprecated proto1 feature) by reading until the
          // matching end-group tag.
          v = BytesValue(Uint8List(0));
          final groupField = field;
          var depth = 1;
          while (p < data.length && depth > 0) {
            final (gKey, gKeyPos) = _readVarint(data, p);
            p = gKeyPos;
            final gField = gKey >> 3;
            final gType = gKey & 7;
            if (gType == 3) {
              depth++;
            } else if (gType == 4 && gField == groupField) {
              depth--;
            }
          }
          break;
        case 4: // end group
          v = BytesValue(Uint8List(0));
        default:
          throw FormatException('Unsupported protobuf wire type $wireType.');
      }
      (fields[field] ??= <ProtoValue>[]).add(v);
    }
    return ProtoMessage(fields);
  }

  int _readFixedLE(List<int> data, int p, int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v |= data[p + i] << (8 * i);
    }
    return v;
  }

  (int, int) _readVarint(List<int> b, int start) {
    var result = 0;
    var shift = 0;
    var p = start;
    while (true) {
      if (p >= b.length) {
        throw const FormatException('Truncated protobuf varint.');
      }
      final byte = b[p++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (result, p);
  }
}

/// A decoded protobuf message: field number → repeated [ProtoValue]s.
class ProtoMessage {
  ProtoMessage(this.fields);

  final Map<int, List<ProtoValue>> fields;

  /// All values for [field], or `null` when absent.
  List<ProtoValue>? operator [](int field) => fields[field];

  /// The first varint value of [field], or `null`.
  int? varint(int field) {
    final vs = fields[field];
    if (vs == null) return null;
    for (final v in vs) {
      if (v is VarintValue) return v.value;
    }
    return null;
  }

  /// The first length-delimited bytes of [field], or `null`.
  Uint8List? bytes(int field) {
    final vs = fields[field];
    if (vs == null) return null;
    for (final v in vs) {
      if (v is BytesValue) return v.bytes;
    }
    return null;
  }

  /// The first length-delimited [field] decoded as UTF-8, or `null` when the
  /// field is absent or the bytes are not valid UTF-8.
  String? string(int field) {
    final b = bytes(field);
    if (b == null) return null;
    try {
      return utf8.decode(b);
    } on FormatException {
      return null;
    }
  }

  /// The first length-delimited [field] decoded as a nested [ProtoMessage].
  /// Returns `null` when the field is absent or the bytes are not a valid
  /// wire-format message.
  ProtoMessage? message(int field) {
    final b = bytes(field);
    if (b == null) return null;
    try {
      return ProtoWire().decode(b);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// All nested messages of [field] (length-delimited values decoded).
  List<ProtoMessage> messages(int field) {
    final vs = fields[field];
    if (vs == null) return const [];
    final out = <ProtoMessage>[];
    for (final v in vs) {
      if (v is! BytesValue) continue;
      try {
        out.add(ProtoWire().decode(v.bytes));
      } on FormatException {
        // Skip malformed nested messages.
      } on RangeError {
        // Skip malformed nested messages.
      }
    }
    return out;
  }

  /// All varint values of [field].
  List<int> varints(int field) {
    final vs = fields[field];
    if (vs == null) return const [];
    return [
      for (final v in vs)
        if (v is VarintValue) v.value,
    ];
  }

  /// All length-delimited byte payloads of [field] (repeated bytes/string).
  List<Uint8List> bytesList(int field) {
    final vs = fields[field];
    if (vs == null) return const [];
    return [
      for (final v in vs)
        if (v is BytesValue) v.bytes,
    ];
  }

  /// The first fixed-64 value of [field] decoded as a double.
  double? double64(int field) {
    final vs = fields[field];
    if (vs == null) return null;
    for (final v in vs) {
      if (v is Fixed64Value) {
        final b = ByteData(8)..setInt64(0, v.value, Endian.little);
        return b.getFloat64(0, Endian.little);
      }
    }
    return null;
  }

  /// All valid UTF-8 strings of [field] (repeated bytes/string).
  List<String> strings(int field) {
    final out = <String>[];
    for (final b in bytesList(field)) {
      try {
        out.add(utf8.decode(b));
      } on FormatException {
        // Skip non-UTF-8 strings.
      }
    }
    return out;
  }
}

/// One decoded field value.
sealed class ProtoValue {
  const ProtoValue();
}

final class VarintValue extends ProtoValue {
  const VarintValue(this.value);
  final int value;
}

final class Fixed64Value extends ProtoValue {
  const Fixed64Value(this.value);
  final int value;
}

final class Fixed32Value extends ProtoValue {
  const Fixed32Value(this.value);
  final int value;
}

final class BytesValue extends ProtoValue {
  const BytesValue(this.bytes);
  final Uint8List bytes;
}
