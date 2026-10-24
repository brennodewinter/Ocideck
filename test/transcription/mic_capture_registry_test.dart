// Welke microfoonbron dit platform registreert (#2516). Desktop krijgt
// een bron; de stub — web, tot #2517 — laat de soort weg.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/channel_mic_port.dart';
import 'package:ocideck/services/transcription/desktop_mic_source.dart';
import 'package:ocideck/services/transcription/linux_mic_recorder_io.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/mic_capture_port.dart';
import 'package:ocideck/services/transcription/mic_capture_registry_io.dart'
    as io;
import 'package:ocideck/services/transcription/mic_capture_registry_stub.dart'
    as stub;
import 'package:ocideck/services/transcription/mic_session_gate.dart';

class _Port extends MicCapturePort {
  @override
  Future<MicPlatformFacts> describe() async =>
      const MicPlatformFacts(availability: CaptureAvailability.available);

  @override
  Future<MicCaptureLive> open({String? deviceId}) =>
      throw UnsupportedError('deze toets opent niet');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop registreert een bron, de stub niet', () async {
    final gate = MicSessionGate();
    final source = io.createDesktopMicrophoneSource(
      port: _Port(),
      gate: gate,
      onLevel: (_) {},
    );
    expect(source, isNotNull);
    expect(source!.kind, CaptureSourceKind.microphone);
    expect(await source.probe(), CaptureAvailability.available);

    expect(
      stub.createDesktopMicrophoneSource(port: _Port(), gate: gate),
      isNull,
    );
    final web = stub.createMicCapturePort();
    final facts = await web.describe();
    expect(facts.availability, CaptureAvailability.unavailable);
    expect(() => web.open(), throwsUnsupportedError);
  });

  test('de poort is het kanaal, of parecord op Linux', () async {
    final created = io.createMicCapturePort();
    if (Platform.isLinux) {
      expect(created, isA<LinuxMicPort>());
      return;
    }
    expect(created, isA<ChannelMicPort>());
    final facts = await created.describe();
    expect(facts.availability, CaptureAvailability.unavailable);
    expect(facts.reason, 'geen microfoonbinding in deze build');
  });

  test(
    'systeemgeluid is een eigen bron en opent niets bij de peiling',
    () async {
      final system = io.createSystemAudioSource();
      expect(system, isNotNull);
      expect(system!.kind, CaptureSourceKind.systemAudio);
      if (!Platform.isLinux) {
        final facts = await (system as DesktopMicrophoneSource).describe();
        expect(facts.availability, CaptureAvailability.unavailable);
        expect(facts.reason, 'geen systeemaudiobinding in deze build');
      }
      expect(stub.createSystemAudioSource(), isNull);
      expect(stub.createWebMicrophoneSource(), isNull);
      expect(stub.createWebDisplaySource(), isNull);
    },
  );
}
