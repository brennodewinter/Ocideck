// Stub voor platforms zonder bestandsroute: de bron bestaat, meldt
// eerlijk "niet beschikbaar" en `describe` faalt getypt. De conditionele
// export in file_capture_source.dart kiest dit bestand alleen waar
// noch dart:io noch de wasm-bridge aanwezig is.
import 'dart:async';

import 'capture_source.dart';
import 'file_capture_source.dart';
import 'transcription_errors.dart';

class StubFileCaptureSource extends FileCaptureSource {
  const StubFileCaptureSource();

  @override
  CaptureSourceKind get kind => CaptureSourceKind.file;

  @override
  Future<CaptureAvailability> probe() async => CaptureAvailability.unavailable;

  @override
  Future<FileSourceInfo> describe(String sourcePath) {
    throw const SourceUnavailable('geen bestandsroute op dit platform');
  }

  @override
  Future<FileCaptureSession> start(CaptureRequest request) {
    throw const SourceUnavailable('geen bestandsroute op dit platform');
  }
}

FileCaptureSource createFileCaptureSource() => const StubFileCaptureSource();
