// Het eigen JS-bronbestand in een geïsoleerde moduleharnas: geen echte WASM
// of ASR-kwaliteitsclaim, wel de productiecallbacks bij abort/herstart.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WASM-bridge herstelt na abort en beschermt actieve contexten',
    () async {
      final result = await Process.run('node', [
        '--test',
        'test/transcription/whisper_bridge_lifecycle_test.cjs',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
