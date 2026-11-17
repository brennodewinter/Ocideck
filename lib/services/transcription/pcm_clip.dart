import 'dart:typed_data';

import 'media_sniff.dart';
import 'transcription_errors.dart';

/// Exact sample boundaries in the already decoded 16 kHz mono PCM16 file.
class PcmClipPlan {
  const PcmClipPlan(this.byteOffset, this.dataBytes);
  final int byteOffset;
  final int dataBytes;
  Duration get duration => Duration(microseconds: dataBytes * 1000000 ~/ 32000);

  Uint8List get header {
    final bytes = encodePcmWav(Float32List(0));
    final view = ByteData.sublistView(bytes);
    view.setUint32(4, 36 + dataBytes, Endian.little);
    view.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }
}

PcmClipPlan planPcmClip(WavInfo info, Duration start, Duration? end) {
  if (info.formatTag != 1 ||
      info.sampleRate != 16000 ||
      info.channels != 1 ||
      info.bitsPerSample != 16 ||
      info.dataBytes.isOdd) {
    throw const DecodeFailed('fragmentbron is geen 16 kHz mono PCM16');
  }
  if (start.isNegative || (end != null && end <= start)) {
    throw const DecodeFailed('ongeldige fragmentgrenzen');
  }
  final total = info.dataBytes ~/ 2;
  final first = (start.inMicroseconds * 16000 + 999999) ~/ 1000000;
  final requestedLast = end == null
      ? total
      : end.inMicroseconds * 16000 ~/ 1000000;
  final last = requestedLast < total ? requestedLast : total;
  if (first >= last) {
    throw const DecodeFailed('het gekozen fragment bevat geen bronaudio');
  }
  return PcmClipPlan(info.dataOffset + first * 2, (last - first) * 2);
}
