// Webhelft van het opnameregister (#2517, #2521). Desktopbronnen
// bestaan hier niet; de browserbronnen wel.
import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'mic_session_gate.dart';
import 'web_media_browser_web.dart';
import 'web_media_source.dart';

final _browser = WebMediaBrowserImpl();

CaptureSource? createDesktopMicrophoneSource({
  required MicCapturePort port,
  required MicSessionGate gate,
  void Function(double level)? onLevel,
}) => null;

MicCapturePort createMicCapturePort() => WebMicPort(_browser);

CaptureSource? createSystemAudioSource() => null;

CaptureSource? createWebMicrophoneSource({MicSessionGate? gate}) =>
    WebMediaSource.microphone(browser: _browser, gate: gate);

CaptureSource? createWebDisplaySource() =>
    WebMediaSource.display(browser: _browser);
