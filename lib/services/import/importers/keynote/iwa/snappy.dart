import 'dart:typed_data';

/// Maximum uncompressed size for a single Snappy raw block (256 MB).
const _maxSnappyBlockSize = 256 * 1024 * 1024;

/// Maximum total uncompressed size for a full `.iwa` framing stream (512 MB).
const _maxSnappyStreamSize = 512 * 1024 * 1024;

/// Pure-Dart Snappy decompressor for Apple iWork IWA streams.
///
/// iWork stores each `.iwa` part as a Snappy **framing** stream (the
/// `sNaPpY` stream-identifier chunk followed by type-0x00 data chunks). Unlike
/// the standard Snappy framing, iWork's data chunks carry **no CRC32C** — the
/// payload is a raw Snappy block (a leading varint uncompressed length followed
/// by the compressed byte stream). This decoder implements both the raw block
/// format and the iWork framing layout, with no native dependencies.
class SnappyDecompressor {
  /// Decompress a full `.iwa` framing stream into one byte buffer.
  ///
  /// Supports the standard Snappy stream-identifier chunk
  /// (`0xff` + 3-byte length `6` + `sNaPpY`) when present, but iWork `.iwa`
  /// files often start with the first data chunk immediately. The
  /// concatenation of every decompressed data chunk is returned; unknown chunk
  /// types are skipped per the framing spec.
  Uint8List decompressIwaStream(List<int> bytes) {
    final out = <int>[];
    var p = 0;
    while (p < bytes.length) {
      if (p + 4 > bytes.length) {
        throw const FormatException('Truncated Snappy framing header.');
      }
      final type = bytes[p];
      final len = bytes[p + 1] | (bytes[p + 2] << 8) | (bytes[p + 3] << 16);
      p += 4;
      if (p + len > bytes.length) {
        throw const FormatException('Snappy chunk length overruns the stream.');
      }
      final payload = bytes.sublist(p, p + len);
      p += len;
      switch (type) {
        case 0xff: // Stream identifier — payload is the "sNaPpY" magic.
          if (!_isSnapMagic(payload)) {
            throw const FormatException('Bad Snappy stream-identifier magic.');
          }
          break;
        case 0x00: // Compressed data (iWork: raw Snappy block, no CRC).
          final decompressed = decodeSnappyRawBlock(payload);
          out.addAll(decompressed);
          _checkStreamSize(out.length);
          break;
        case 0x01: // Uncompressed data (standard Snappy framing).
          out.addAll(payload);
          _checkStreamSize(out.length);
          break;
        default:
          // 0xfe (padding), etc. — skip safely.
          break;
      }
    }
    if (out.isEmpty) {
      throw const FormatException('No Snappy data chunks found.');
    }
    return Uint8List.fromList(out);
  }

  /// Decompress one raw Snappy block: a leading varint uncompressed length,
  /// then the compressed instruction stream. Used by [decompressIwaStream]
  /// and exposed for direct block decoding.
  Uint8List decodeSnappyRawBlock(List<int> block) {
    final (outLen, p0) = _readVarint(block, 0);
    if (outLen > _maxSnappyBlockSize) {
      throw FormatException(
        'Snappy block uncompressed size $outLen exceeds limit $_maxSnappyBlockSize.',
      );
    }
    final out = Uint8List(outLen);
    var ip = p0;
    var op = 0;
    while (ip < block.length) {
      final tag = block[ip++];
      switch (tag & 3) {
        case 0:
          // Literal: high 6 bits encode length-1, or an extended length.
          var len = (tag >> 2) + 1;
          if (len > 60) {
            final n = len - 60; // number of length bytes (1..4)
            int l = 0;
            for (var i = 0; i < n; i++) {
              l |= block[ip++] << (8 * i);
            }
            len = l + 1;
          }
          for (var i = 0; i < len; i++) {
            out[op++] = block[ip++];
          }
        case 1:
          // Copy with 1-byte offset.
          final len = ((tag >> 2) & 0x7) + 4;
          final offset = ((tag >> 5) & 0x7) * 256 + block[ip++];
          _copy(out, op, offset, len);
          op += len;
        case 2:
          // Copy with 2-byte offset (little-endian).
          final len = (tag >> 2) + 1;
          final offset = block[ip++] | (block[ip++] << 8);
          _copy(out, op, offset, len);
          op += len;
        case 3:
          // Copy with 4-byte offset (little-endian).
          final len = (tag >> 2) + 1;
          final offset =
              block[ip++] |
              (block[ip++] << 8) |
              (block[ip++] << 16) |
              (block[ip++] << 24);
          _copy(out, op, offset, len);
          op += len;
      }
    }
    return out;
  }

  /// Overlap-safe copy: read [len] bytes from `op - offset` in [out].
  void _copy(Uint8List out, int op, int offset, int len) {
    final start = op - offset;
    if (start < 0 || offset <= 0) {
      throw const FormatException('Invalid Snappy copy offset.');
    }
    for (var i = 0; i < len; i++) {
      out[op + i] = out[start + i];
    }
  }

  /// True when [payload] is the Snappy stream-identifier magic `sNaPpY`.
  bool _isSnapMagic(List<int> payload) {
    const magic = [0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]; // s N a P p Y
    if (payload.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (payload[i] != magic[i]) return false;
    }
    return true;
  }

  void _checkStreamSize(int length) {
    if (length > _maxSnappyStreamSize) {
      throw FormatException(
        'Snappy stream uncompressed size $length exceeds limit $_maxSnappyStreamSize.',
      );
    }
  }

  /// LEB128 varint at [start]; returns `(value, nextOffset)`.
  (int, int) _readVarint(List<int> b, int start) {
    var result = 0;
    var shift = 0;
    var p = start;
    while (true) {
      final byte = b[p++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (result, p);
  }
}
