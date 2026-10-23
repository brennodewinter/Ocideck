// Browserhelft van de platformprobe (#2514): de eigenschappen die
// bepalen welke transcriptieroutes op deze pagina kunnen — secure context
// (zonder https geen WebCrypto, dus geen hashverificatie), cross-origin
// isolatie (zonder COOP/COEP geen SharedArrayBuffer, dus geen wasm-engine),
// MediaRecorder + MIME-steun (de invoerkant van opname) en de
// opslagquota-schatting. Allemaal passief: getters, geen permissie.
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../utils/log.dart';
import 'environment_probe.dart';
import 'model_store_web.dart' show storageFreeBytes;

/// De containers die de recorder-routes zullen vragen. Kort en realistisch:
/// webm/opus is de brede route, mp4 de Safari-route, ogg de oude Firefox.
const _audioMimeCandidates = {
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4',
  'audio/ogg;codecs=opus',
};

Future<TranscriptionEnvironment> probeTranscriptionEnvironment() async {
  final hasRecorder = web.window.has('MediaRecorder');
  final supported = <String>{};
  if (hasRecorder) {
    for (final mime in _audioMimeCandidates) {
      try {
        if (web.MediaRecorder.isTypeSupported(mime)) supported.add(mime);
      } on Object catch (e, s) {
        logError('environmentProbeWeb: isTypeSupported', e, s);
      }
    }
  }
  return TranscriptionEnvironment(
    platformLabel: 'web',
    secureContext: web.window.isSecureContext,
    crossOriginIsolated: web.window.crossOriginIsolated,
    mediaRecorderAvailable: hasRecorder,
    supportedAudioMimes: supported,
    freeStorageBytes: await storageFreeBytes(),
  );
}
