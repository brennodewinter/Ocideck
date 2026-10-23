import 'dart:io';

import 'capture_source.dart';
import 'channel_mic_port.dart';
import 'desktop_mic_source.dart';
import 'linux_mic_recorder.dart';
import 'mic_capture_port.dart';
import 'mic_session_gate.dart';

CaptureSource? createDesktopMicrophoneSource({
  required MicCapturePort port,
  required MicSessionGate gate,
  void Function(double level)? onLevel,
}) {
  return DesktopMicrophoneSource(
    port: port,
    gate: gate,
    freeBytes: _freeBytes,
    onLevel: onLevel,
  );
}

MicCapturePort createMicCapturePort() {
  if (Platform.isLinux) return LinuxMicPort();
  return ChannelMicPort();
}

/// Systeem- of appgeluid. Linux gebruikt een uitvoermonitor; macOS en
/// Windows een eigen kanaal. Null bestaat hier niet: afwezigheid zegt
/// de bron zelf via [CaptureSource.probe].
CaptureSource? createSystemAudioSource() {
  final port = Platform.isLinux ? LinuxMonitorPort() : ChannelMicPort.system();
  return DesktopMicrophoneSource.system(port: port, freeBytes: _freeBytes);
}

/// Web heeft zijn eigen bron (#2517). Op desktop is die er niet.
CaptureSource? createWebMicrophoneSource({MicSessionGate? gate}) => null;

/// Tab- of schermgeluid is een webroute (#2521).
CaptureSource? createWebDisplaySource() => null;

Future<int?> _freeBytes(String directory) {
  if (Platform.isLinux) return dfFreeBytes(directory);
  return ChannelMicPort().freeBytes(directory);
}
