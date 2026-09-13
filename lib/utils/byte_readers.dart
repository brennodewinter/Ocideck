import 'dart:typed_data';

/// Little-endian 16-bit reader: bytes[o] | (bytes[o+1] << 8).
int readUint16LE(Uint8List d, int o) => d[o] | (d[o + 1] << 8);

/// Big-endian 16-bit reader: (bytes[o] << 8) | bytes[o+1].
int readUint16BE(Uint8List d, int o) => (d[o] << 8) | d[o + 1];

/// Little-endian 32-bit reader.
int readUint32LE(Uint8List d, int o) =>
    d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

/// Big-endian 32-bit reader.
int readUint32BE(Uint8List d, int o) =>
    (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
