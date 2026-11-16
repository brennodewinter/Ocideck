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
  WebMediaBrowserImpl({this.stopTimeout = const Duration(seconds: 10)});

  final Duration stopTimeout;

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
    try {
      return await _record(stream);
    } on Object {
      _stopTracks(stream);
      rethrow;
    }
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
    return _BrowserRecording(recorder, stream, stopTimeout).start();
  }
}

class _BrowserRecording {
  _BrowserRecording(this.recorder, this.stream, this.timeout);

  final web.MediaRecorder recorder;
  final web.MediaStream stream;
  final Duration timeout;
  final chunks = StreamController<Uint8List>();
  final ended = StreamController<CaptureEndCause>.broadcast();
  final stopped = Completer<void>();
  Future<void> reads = Future<void>.value();
  Future<void>? stopFuture;
  DecodeFailed? readFailure;
  bool finishing = false;
  bool endEmitted = false;

  WebMediaLive start() {
    recorder.ondataavailable = ((web.Event event) {
      final blob = (event as web.BlobEvent).data;
      if (blob.size == 0 || chunks.isClosed) return;
      // Eén keten bewaart de eventvolgorde en vangt ook mislukte Blob-reads.
      reads = reads
          .then((_) => _emit(blob, chunks).timeout(timeout))
          .catchError((Object _) {
            readFailure ??= const DecodeFailed(
              'browseraudioblok kon niet worden gelezen',
            );
            signalEnd(CaptureEndCause.storageFailed);
          });
    }).toJS;
    recorder.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
      if (!finishing) signalEnd(CaptureEndCause.sourceLost);
    }).toJS;
    recorder.onerror = ((web.Event _) {
      signalEnd(CaptureEndCause.sourceLost);
    }).toJS;
    for (final track in stream.getTracks().toDart) {
      track.onended = ((web.Event _) => signalEnd(
        CaptureEndCause.sourceLost,
      )).toJS;
    }
    recorder.start(1000);
    return WebMediaLive(
      chunks: chunks.stream,
      ended: ended.stream,
      mime: recorder.mimeType,
      stop: stop,
    );
  }

  void signalEnd(CaptureEndCause cause) {
    if (!finishing && !endEmitted && !ended.isClosed) {
      endEmitted = true;
      ended.add(cause);
    }
  }

  Future<void> stop() => stopFuture ??= finish();

  Future<void> finish() async {
    finishing = true;
    try {
      if (recorder.state != 'inactive') recorder.stop();
      // Ook bij een al inactieve recorder kan het laatste data-event nog komen.
      await stopped.future.timeout(timeout);
      await reads.timeout(timeout);
      final failure = readFailure;
      if (failure != null) throw failure;
    } on TimeoutException {
      throw const IoFailed('browseropname stopte niet op tijd');
    } on TranscriptionError {
      rethrow;
    } on Object {
      throw const SourceUnavailable('browseropname kon niet afronden');
    } finally {
      recorder.ondataavailable = null;
      recorder.onstop = null;
      recorder.onerror = null;
      for (final track in stream.getTracks().toDart) {
        track.onended = null;
      }
      _stopTracks(stream);
      if (!chunks.isClosed) await chunks.close();
      if (!ended.isClosed) await ended.close();
    }
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

void _stopTracks(web.MediaStream stream) {
  for (final track in stream.getTracks().toDart) {
    track.stop();
  }
}
