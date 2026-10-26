import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'mic_session_gate.dart';

/// Geen desktoproute. De webhelft vult de microfoon zelf (#2517).
CaptureSource? createDesktopMicrophoneSource({
  required MicCapturePort port,
  required MicSessionGate gate,
  void Function(double level)? onLevel,
}) => null;

MicCapturePort createMicCapturePort() => const _NoMicPort();

CaptureSource? createSystemAudioSource() => null;

CaptureSource? createWebMicrophoneSource({MicSessionGate? gate}) => null;

CaptureSource? createWebDisplaySource() => null;

/// Geen bestandssysteem-staging op web, dus ook geen vrije-ruimtemeting.
Future<int?> recordingFreeBytes(String directory) async => null;

class _NoMicPort extends MicCapturePort {
  const _NoMicPort();

  @override
  Future<MicPlatformFacts> describe() async => const MicPlatformFacts(
    availability: CaptureAvailability.unavailable,
    reason: 'geen desktop-microfoon op dit platform',
  );

  @override
  Future<MicCaptureLive> open({String? deviceId}) {
    throw UnsupportedError('geen desktop-microfoon op dit platform');
  }
}
