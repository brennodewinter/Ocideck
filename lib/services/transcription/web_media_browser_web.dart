// De echte browser achter [WebMediaBrowser]. Alleen op web gecompileerd.
// Beslissingen over beschikbaarheid staan in `web_media_source.dart`;
// hier blijven de aanroepen die een toestemmingsvenster kunnen openen.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'capture_source.dart';
import 'transcription_errors.dart';
import 'web_media_source.dart';

class WebMediaBrowserImpl implements WebMediaBrowser {
  @override
  Future<CaptureAvailability> probeMicrophone() async {
    return microphoneAvailability(
      secure: web.window.isSecureContext,
      hasRecorder: web.window.has('MediaRecorder'),
      hasUserMedia: _hasMedia('getUserMedia'),
    );
  }

  @override
  Future<CaptureAvailability> probeDisplay() async {
    return displayAvailability(
      secure: web.window.isSecureContext,
      hasRecorder: web.window.has('MediaRecorder'),
      hasDisplayMedia: _hasMedia('getDisplayMedia'),
      userAgent: web.window.navigator.userAgent,
    );
  }

  @override
  Future<WebMediaLive> openMicrophone() => _open(display: false);

  @override
  Future<WebMediaLive> openDisplay() => _open(display: true);

  Future<WebMediaLive> _open({required bool display}) async {
    final web.MediaStream stream;
    try {
      stream = display ? await _displayStream() : await _micStream();
    } on Object catch (error) {
      final text = error.toString();
      if (text.contains('NotAllowedError') || text.contains('SecurityError')) {
        throw const PermissionDenied('de browser weigerde de opname');
      }
      throw const SourceUnavailable('de browseropname kon niet starten');
    }
    if (display && stream.getAudioTracks().toDart.isEmpty) {
      _stopTracks(stream);
      throw const SourceUnavailable(webDisplaySilentMessage);
    }
    return _record(stream);
  }

  Future<web.MediaStream> _micStream() {
    return web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
  }

  Future<web.MediaStream> _displayStream() {
    return web.window.navigator.mediaDevices
        .getDisplayMedia(
          web.DisplayMediaStreamOptions(video: true.toJS, audio: true.toJS),
        )
        .toDart;
  }

  Future<WebMediaLive> _record(web.MediaStream stream) async {
    final mime = _mime();
    final recorder = mime == null
        ? web.MediaRecorder(stream)
        : web.MediaRecorder(stream, web.MediaRecorderOptions(mimeType: mime));
    final chunks = StreamController<Uint8List>();
    final stopped = Completer<void>();
    recorder.ondataavailable = ((web.Event event) {
      final blob = (event as web.BlobEvent).data;
      if (blob.size == 0) return;
      unawaited(_emit(blob, chunks));
    }).toJS;
    recorder.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    recorder.start(1000);
    return WebMediaLive(
      chunks: chunks.stream,
      mime: recorder.mimeType,
      stop: () => _stop(recorder, stream, chunks, stopped),
    );
  }
}

bool _hasMedia(String name) {
  try {
    return web.window.navigator.mediaDevices.has(name);
  } on Object {
    return false;
  }
}

String? _mime() {
  const candidates = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/mp4',
    'audio/ogg;codecs=opus',
  ];
  for (final mime in candidates) {
    if (web.MediaRecorder.isTypeSupported(mime)) return mime;
  }
  return null;
}

Future<void> _emit(web.Blob blob, StreamController<Uint8List> chunks) async {
  if (chunks.isClosed) return;
  final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
  if (!chunks.isClosed && bytes.isNotEmpty) chunks.add(bytes);
}

Future<void> _stop(
  web.MediaRecorder recorder,
  web.MediaStream stream,
  StreamController<Uint8List> chunks,
  Completer<void> stopped,
) async {
  if (recorder.state != 'inactive') {
    try {
      recorder.stop();
    } on Object {
      if (!stopped.isCompleted) stopped.complete();
    }
  } else if (!stopped.isCompleted) {
    stopped.complete();
  }
  await stopped.future;
  _stopTracks(stream);
  if (!chunks.isClosed) await chunks.close();
}

void _stopTracks(web.MediaStream stream) {
  for (final track in stream.getTracks().toDart) {
    track.stop();
  }
}
