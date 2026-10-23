// De platformprobe uit #2514: de io-helft rapporteert wat `dart:io`
// passief weet, de stubhelft meldt eerlijk "dit platform" — en de facade
// kiest daar op de VM de io-variant bij (dart.library.io staat in de
// conditionele import vóór js_interop).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/environment_probe.dart';
import 'package:ocideck/services/transcription/environment_probe_io.dart'
    as io_probe;
import 'package:ocideck/services/transcription/environment_probe_stub.dart'
    as stub_probe;

void main() {
  test(
    'de facade rapporteert het desktop-OS en de processorarchitectuur',
    () async {
      final env = await probeTranscriptionEnvironment();
      expect(env.platformLabel, isNotEmpty);
      // Op de test-VM draait dart:io — de webvelden blijven dan eerlijk null.
      expect(env.architecture, isNotNull);
      expect(env.secureContext, isNull);
      expect(env.crossOriginIsolated, isNull);
      expect(env.mediaRecorderAvailable, isNull);
      expect(env.supportedAudioMimes, isEmpty);
      expect(env.freeStorageBytes, isNull);
    },
  );

  test('de io-helft levert naam plus architectuur, geen webfeiten', () async {
    final env = await io_probe.probeTranscriptionEnvironment();
    expect(env.platformLabel, isNotEmpty);
    expect(env.architecture, isNotNull);
    expect(env.crossOriginIsolated, isNull);
  });

  test('de stub zegt alleen "dit platform" — geen geraden feiten', () async {
    final env = await stub_probe.probeTranscriptionEnvironment();
    expect(env.platformLabel, 'dit platform');
    expect(env.architecture, isNull);
    expect(env.secureContext, isNull);
    expect(env.crossOriginIsolated, isNull);
    expect(env.mediaRecorderAvailable, isNull);
    expect(env.supportedAudioMimes, isEmpty);
    expect(env.freeStorageBytes, isNull);
  });
}
