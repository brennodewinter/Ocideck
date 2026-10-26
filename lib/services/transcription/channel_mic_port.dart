// Method-channel naar de macOS- en Windows-binding (#2516).
//
// Het kanaal `ocideck/mic_capture` kent `describe`, `open`, `stop` en
// `freeBytes`. PCM komt binnen op `ocideck/mic_capture_pcm` als ruwe
// s16le-blokken; een einde is een map `{event: ended, cause: ...}`.
// `describe` en `freeBytes` openen geen apparaat. Ontbreekt de binding
// (een widgettest, een build zonder de native helft), dan is de route
// eerlijk niet beschikbaar in plaats van een ontbrekende plugin.
import 'dart:async';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'transcription_errors.dart';

const micCaptureChannelName = 'ocideck/mic_capture';
const micCapturePcmChannelName = 'ocideck/mic_capture_pcm';

/// Systeem- of appgeluid (#2518, #2519). Apart kanaal, zodat een
/// microfoon-`open` nooit per ongeluk de uitvoermix pakt.
const systemCaptureChannelName = 'ocideck/system_capture';
const systemCapturePcmChannelName = 'ocideck/system_capture_pcm';

TranscriptionError micErrorFromPlatform(String code, String? message) {
  final text = (message == null || message.isEmpty) ? code : message;
  return switch (code) {
    'permissionDenied' => PermissionDenied(text),
    'unsupported' => UnsupportedSource(text),
    'ioFailed' => IoFailed(text),
    _ => SourceUnavailable(text),
  };
}

class ChannelMicPort extends MicCapturePort {
  ChannelMicPort({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(micCaptureChannelName),
      _events = events ?? const EventChannel(micCapturePcmChannelName);

  final MethodChannel _methods;
  final EventChannel _events;

  /// De desktopbinding voor systeemgeluid. Ontbreekt die, dan zegt
  /// [describe] `unavailable` — geen crash, geen stille microfoon.
  factory ChannelMicPort.system() => ChannelMicPort(
    methods: const MethodChannel(systemCaptureChannelName),
    events: const EventChannel(systemCapturePcmChannelName),
  );

  @override
  Future<MicPlatformFacts> describe() async {
    try {
      final raw = await _methods.invokeMapMethod<Object?, Object?>('describe');
      return MicPlatformFacts.fromMap(raw);
    } on MissingPluginException {
      return MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: _methods.name == systemCaptureChannelName
            ? 'geen systeemaudiobinding in deze build'
            : 'geen microfoonbinding in deze build',
      );
    } on PlatformException catch (e) {
      return MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: e.message ?? e.code,
      );
    }
  }

  Future<int?> freeBytes(String directory) async {
    try {
      return await _methods.invokeMethod<int>('freeBytes', {'path': directory});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      // Geen binding (een test zonder widgetlaag) — onmeetbaar is het
      // zelfde antwoord als een afwezige plugin.
      return null;
    }
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    final live = _ChannelLive(_methods, _events);
    try {
      final raw = await _methods.invokeMapMethod<Object?, Object?>('open', {
        'deviceId': ?deviceId,
      });
      final rate = raw?['sampleRate'];
      final channels = raw?['channels'];
      if (rate is! int || channels is! int || rate <= 0 || channels <= 0) {
        await live.stop();
        throw const SourceUnavailable('het platform gaf geen audioklok');
      }
      live.format = MicStreamFormat(sampleRate: rate, channels: channels);
      return live;
    } on TranscriptionError {
      await live.stop();
      rethrow;
    } on MissingPluginException {
      await live.stop();
      throw const SourceUnavailable('geen microfoonbinding in deze build');
    } on PlatformException catch (e) {
      await live.stop();
      throw micErrorFromPlatform(e.code, e.message);
    }
  }
}

class _ChannelLive implements MicCaptureLive {
  _ChannelLive(this._methods, EventChannel events) {
    _sub = events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        if (_stopped) return;
        if (error is PlatformException) {
          _ended.add(
            error.code == 'permissionDenied'
                ? CaptureEndCause.permissionRevoked
                : CaptureEndCause.sourceLost,
          );
          return;
        }
        _ended.add(CaptureEndCause.sourceLost);
      },
    );
  }

  final MethodChannel _methods;
  final _frames = StreamController<MicPcmFrame>.broadcast();
  final _ended = StreamController<CaptureEndCause>.broadcast();
  StreamSubscription<dynamic>? _sub;
  var _stopped = false;

  @override
  late MicStreamFormat format;

  @override
  Stream<MicPcmFrame> get frames => _frames.stream;

  @override
  Stream<CaptureEndCause> get ended => _ended.stream;

  void _onEvent(Object? event) {
    if (_stopped) return;
    if (event is Uint8List) {
      // De standaardcodec levert Uint8List. Een kale List<int> is
      // dezelfde lading uit een testfake.
      _frames.add(MicPcmFrame(event));
      return;
    }
    if (event is List<int>) {
      _frames.add(MicPcmFrame(Uint8List.fromList(event)));
      return;
    }
    if (event is Map && event['event'] == 'ended') {
      _ended.add(
        event['cause'] == 'permissionRevoked'
            ? CaptureEndCause.permissionRevoked
            : CaptureEndCause.sourceLost,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sub?.cancel();
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      // De binding was er niet. Er is dan ook geen apparaat om vrij te geven.
    } on PlatformException {
      // Stoppen moet slagen ook als het apparaat al weg is.
    }
    if (!_frames.isClosed) await _frames.close();
    if (!_ended.isClosed) await _ended.close();
  }
}
