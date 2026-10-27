// De callaudiobron als [CaptureSource] (#2529, TRANSCRIPTION.md §4.1).
//
// De bewezen tap uit #2527 levert gedecodeerde PCM per bron; dit bestand
// beslist wat er een *opname* van is: één afspeelbare mix op 16 kHz mono
// naast losse bronbestanden met hun provenance, gevoed door een
// tick-mixer. Een tick-mix is nodig omdat bronnen interleaved en met
// gaten leveren — bronnen naast elkaar in één file zou de tijdlijn
// verdubbelen en is geen afspeelbare opname.
//
// Drie contracten die de mix waakt:
//  * een gemute of weggevallen bron levert stilte, géén audio — de
//    tijdlijn loopt door (starving → stilte-ticks);
//  * dezelfde deelnemerstrack komt nooit dubbel in een bestand: de
//    tap dedupt op track-id, de gate op bron+tijdstip;
//  * luidsprekerloopback kan per constructie niet: wat hier binnenkomt
//    is de gedecodeerde stroom, niet de uitgaande bus van het apparaat.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

import '../services/transcription/capture_source.dart';
import '../services/transcription/desktop_mic_source.dart'
    show FreeBytes, minFreeBytesForRecording;
import '../services/transcription/mic_capture_registry_stub.dart'
    if (dart.library.io) '../services/transcription/mic_capture_registry_io.dart'
    as registry;
import '../services/transcription/transcription_errors.dart';
import '../services/transcription/wav_sink.dart';
import '../services/transcription/wav_sink_stub.dart'
    if (dart.library.io) '../services/transcription/wav_sink_io.dart'
    as wav_file;
import '../services/web_asset_store.dart';
import 'call_audio_manifest.dart' as manifest;
import 'call_audio_source.dart';
import 'meeting_provider.dart';

/// Emissie-eenheid van de mixer: 20 ms × 16 kHz × s16le mono.
const callAudioTickBytes = 640;

/// Hoe lang een bron zonder frames wacht vóór hij als stil meedoet. Kort
/// genoeg om jitter niet als stilte te schrijven, lang genoeg dat een
/// gemute track of een reconnect-gap wel als stilte vastligt.
const _starveAfter = Duration(seconds: 2);

/// De ingestuurde drain — periodiek zodat óók een volledige stilstand
/// (alle bronnen starving) de tijdlijn van de file laat doorlopen.
const _drainInterval = Duration(milliseconds: 250);

/// Neemt de hele call op via de bewezen tap van [MeetingSession]. De
/// capability staat in `probe`; `start` faalt gesloten als de sessie
/// geen whole-call-bron claimt.
class CallAudioCaptureSource extends CaptureSource {
  CallAudioCaptureSource({
    required this.session,
    FreeBytes? freeBytes,
    this.maxRecordingBytes = maxRecordingWavBytes,
  }) : _freeBytes = freeBytes ?? registry.recordingFreeBytes,
       kind = CaptureSourceKind.callAudio;

  /// De lopende call die deze bron voedt; [start] opent er de tap op.
  final MeetingSession session;
  final FreeBytes _freeBytes;
  final int maxRecordingBytes;

  @override
  final CaptureSourceKind kind;

  /// Goedkoop en stil: het feit staat al op de sessie — geen prompt,
  /// geen device-open, geen netwerk (§2.1).
  @override
  Future<CaptureAvailability> probe() async =>
      session.capabilities.callAudio.wholeCall
      ? CaptureAvailability.available
      : CaptureAvailability.unavailable;

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    if (request.kinds.length != 1 || !request.kinds.contains(kind)) {
      throw const UnsupportedSource('deze route neemt alleen call-audio op');
    }
    if (!session.capabilities.callAudio.wholeCall) {
      throw const SourceUnavailable(
        'deze vergadering levert geen aparte audiobron',
      );
    }
    final stagingDir = request.stagingDir;
    if (stagingDir != null) {
      final free = await _freeBytes(stagingDir);
      if (free != null && free < minFreeBytesForRecording) {
        throw const CapacityExceeded(
          'te weinig vrije schijfruimte om een opname te starten',
        );
      }
    }
    final stream = session.startCallAudioCapture();
    return _CallAudioSession(
      stream: stream,
      session: session,
      stagingDir: stagingDir,
      maxBytes: maxRecordingBytes,
    );
  }
}

/// Eén aangeboden bron binnen de opname: pending bytes, zijn eigen
/// WAV (desktop) en de provenance die het manifest vastlegt.
class _Src {
  _Src(this.index, CallAudioChunk first)
    : trackId = first.trackId,
      role = first.role,
      participantId = first.participantId,
      lastFrameAt = first.at,
      lastDeliveredAt = clock.now(),
      firstAt = first.at;

  final int index;
  final String trackId;
  final CallAudioRole role;
  final String participantId;
  final DateTime firstAt;

  /// Laatste *capture*-tijdstip — provenance voor het manifest.
  DateTime lastFrameAt;

  /// Laatste *lever*tijdstip — de starvatiekloof die stilte-ticks beslist
  /// meet tegen levering, niet tegen wat de adapter stempelde.
  DateTime lastDeliveredAt;

  var frames = 0;
  var silenceTicks = 0;
  wav_file.IncrementalWav? wav;

  final _pending = <Uint8List>[];
  var pendingBytes = 0;

  /// [pcm] is al 16 kHz mono — de resample hoort bij de gate, niet hier.
  void feed(CallAudioChunk c, Uint8List pcm) {
    _pending.add(pcm);
    pendingBytes += pcm.length;
    lastFrameAt = c.at;
    lastDeliveredAt = clock.now();
    frames++;
  }

  /// Consumeert hooguit [n] bytes; tekort wordt met stilte aangevuld —
  /// precies wat een starving of beëindigde bron op dit tick bijdraagt.
  Uint8List take(int n) {
    final out = Uint8List(n);
    var off = 0;
    while (off < n && _pending.isNotEmpty) {
      final head = _pending.first;
      final need = n - off;
      if (head.length <= need) {
        out.setRange(off, off + head.length, head);
        off += head.length;
        _pending.removeAt(0);
      } else {
        out.setRange(off, n, head.sublist(0, need));
        _pending[0] = head.sublist(need);
        off = n;
      }
    }
    pendingBytes -= off;
    if (off < n) silenceTicks++;
    return out;
  }

  String get fileName => 'call-${role.name}-$index.wav';
}

/// De lopende opname. Schrijft vanaf de eerste tick incrementeel —
/// een crash kost nooit meer dan de nog ongeschreven staart (§3.2).
class _CallAudioSession implements CaptureSession {
  _CallAudioSession({
    required Stream<CallAudioChunk> stream,
    required MeetingSession session,
    required String? stagingDir,
    required int maxBytes,
  }) : _session = session,
       _stagingDir = stagingDir,
       _maxBytes = maxBytes {
    _gate = CallAudioGate(session.capabilities.callAudio);
    _sub = stream.listen(
      _onChunk,
      onError: (_) => _emit(CaptureEndCause.sourceLost),
      onDone: () => _emit(CaptureEndCause.sourceLost),
    );
    _ticker = Timer.periodic(_drainInterval, (_) {
      if (!_draining) _drainFuture = _drain();
    });
    if (stagingDir != null) {
      // Alleen de file aanmaken — het openen gebeurt lazily bij de eerste
      // tick, zodat `add` nooit op een half-geopende file landt.
      _mixWav = wav_file.IncrementalWav(
        p.join(stagingDir, recordingWavName),
        maxBytes: maxBytes,
      );
    }
  }

  final MeetingSession _session;
  final String? _stagingDir;
  final int _maxBytes;
  late final CallAudioGate _gate;
  late final StreamSubscription<CallAudioChunk> _sub;
  late final Timer _ticker;

  final _srcs = <String, _Src>{};
  var _nextIndex = 0;
  wav_file.IncrementalWav? _mixWav;
  var _mixOpened = false;
  final _mixMem = BytesBuilder(copy: false); // web: bytes voor mem:-asset

  final _ended = StreamController<CaptureEndCause>.broadcast();
  final _liveOut = StreamController<AudioChunk>.broadcast();
  final _startedAt = clock.now();
  var _emitted = Duration.zero;
  var _draining = false;
  Future<void>? _drainFuture;
  var _stopping = false;
  var _dead = false;
  String _storedPath = '';
  Future<RecordedAudio>? _stopFuture;

  @override
  String get durablePath =>
      _storedPath.isNotEmpty ? _storedPath : (_mixWav?.path ?? '');

  @override
  Stream<AudioChunk>? get liveChunks => _liveOut.stream;

  @override
  Stream<CaptureEndCause>? get ended => _ended.stream;

  void _emit(CaptureEndCause cause) {
    if (_ended.isClosed || _stopping) return;
    _dead = true;
    _ended.add(cause);
  }

  void _onChunk(CallAudioChunk c) {
    if (_dead || _stopping) return;
    final localMuted = _session.participants.any(
      (p) => p.isLocal && p.micMuted,
    );
    final kept = _gate.consider(c, localMuted: localMuted);
    if (kept == null) return;
    // De mix spreekt alleen 16 kHz mono s16le. De webrtc-adapter levert
    // dat al; deze stap is het contract zelf — een tap die z'n rate niet
    // meegeeft corrumpeert de file niet stil mee.
    final f = callPcmFrame16k(kept.pcm, kept.sampleRateHz, 1);
    if (f.pcm.isEmpty) return;
    final src = _srcs.putIfAbsent(kept.trackId, () => _Src(_nextIndex++, kept));
    src.feed(kept, f.pcm);
    if (!_draining) _drainFuture = _drain();
  }

  /// Emit ticks zolang elke bekende bron óf een tick heeft óf starving
  /// is, en de file nooit voor op de klok loopt — anders zou een stille
  /// periode de file in een hot loop vullen, ver voor op de echte tijd.
  /// Een bron die nog niet starving is blokkeert: zijn volgende brok of
  /// zijn timeout beslist, nooit een gok.
  Future<void> _drain() async {
    _draining = true;
    try {
      while (!_dead && !_stopping && _srcs.isNotEmpty) {
        final now = clock.now();
        if (_emitted >= now.difference(_startedAt)) break;
        var blocked = false;
        // Snapshot: `_onChunk` kan een nieuwe bron toevoegen terwijl de
        // file-IO van een tick pauzeert — itereren over de live-map zou
        // dan crashen of de nieuwe bron halveerwege meetellen.
        for (final s in _srcs.values.toList()) {
          if (s.pendingBytes >= callAudioTickBytes) continue;
          if (now.difference(s.lastDeliveredAt) < _starveAfter) {
            blocked = true;
            break;
          }
        }
        if (blocked) break;
        await _emitTick(callAudioTickBytes);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _emitTick(int n) async {
    final slices = <Uint8List>[];
    for (final s in _srcs.values.toList()) {
      final slice = s.take(n);
      final wav = s.wav ?? await _openSrcWav(s);
      if (wav != null) {
        try {
          await wav.add(slice);
        } on IoFailed {
          _emit(CaptureEndCause.storageFailed);
          return;
        }
      }
      slices.add(slice);
    }
    final mix = _mixSlices(slices, n);
    try {
      final wav = _mixWav;
      if (wav != null) {
        if (!_mixOpened) {
          _mixOpened = await _openWav(wav);
          if (!_mixOpened) throw const IoFailed('opnamebestand opent niet');
        }
        await wav.add(mix);
      } else {
        _mixMem.add(mix);
        if (_mixMem.length > _maxBytes) {
          throw const IoFailed('de opname past niet in het geheugen');
        }
      }
    } on IoFailed {
      _emit(CaptureEndCause.storageFailed);
      return;
    }
    if (!_liveOut.isClosed) {
      _liveOut.add(AudioChunk(bytes: mix, offset: _emitted));
    }
    _emitted += Duration(
      microseconds: (n / 2 / recordingSampleRate * 1000000).round(),
    );
  }

  /// De eigen file van een bron, lazily bij zijn eerste tick. Mislukte
  /// open = storageFailed; null op web (daar is alleen de mix duurzaam).
  Future<wav_file.IncrementalWav?> _openSrcWav(_Src s) async {
    final dir = _stagingDir;
    if (dir == null || s.wav != null) return s.wav;
    final wav = wav_file.IncrementalWav(
      p.join(dir, s.fileName),
      maxBytes: _maxBytes,
    );
    if (!await _openWav(wav)) {
      _emit(CaptureEndCause.storageFailed);
      return null;
    }
    s.wav = wav;
    return wav;
  }

  static Future<bool> _openWav(wav_file.IncrementalWav wav) async {
    try {
      await wav.open();
      return true;
    } on Object {
      return false;
    }
  }

  /// s16le-som met clipping — de gebruikelijke, veilige mix voor spraak.
  static Uint8List _mixSlices(List<Uint8List> slices, int n) {
    if (slices.length == 1) return slices.first;
    final out = Uint8List(n);
    final od = ByteData.sublistView(out);
    final views = slices.map(ByteData.sublistView).toList();
    for (var i = 0; i + 1 < n; i += 2) {
      var acc = 0;
      for (final v in views) {
        acc += v.getInt16(i, Endian.little);
      }
      od.setInt16(i, acc.clamp(-32768, 32767), Endian.little);
    }
    return out;
  }

  @override
  Future<RecordedAudio> stop() => _stopFuture ??= _stop();

  Future<RecordedAudio> _stop() async {
    _stopping = true;
    _ticker.cancel();
    await _sub.cancel();
    final drain = _drainFuture;
    if (drain != null) await drain;
    // De rest van elke buffer als één slot-tick: de langste bepaalt de
    // lengte, kortere bronnen vullen met stilte — alle files even lang.
    // Ook bij een dode bron: wat er staat hoort in de file, niet weg.
    final rest = _srcs.values.fold<int>(
      0,
      (m, s) => s.pendingBytes > m ? s.pendingBytes : m,
    );
    if (_srcs.isNotEmpty && rest >= 2) {
      await _emitTick(rest & ~1);
    }
    for (final s in _srcs.values) {
      final wav = s.wav;
      if (wav != null) {
        try {
          await wav.close();
        } on IoFailed {
          await wav_file.repairWavHeader(wav.path);
        }
      }
    }
    final mixWav = _mixWav;
    if (mixWav != null) {
      try {
        await mixWav.close();
      } on IoFailed {
        await wav_file.repairWavHeader(mixWav.path);
      }
      _storedPath = mixWav.path;
      await manifest.writeCallSources(_stagingDir!, _manifestJson());
    } else if (_mixMem.isNotEmpty) {
      // Web: het geheugen is de duurzame plek — mix als wav, manifest
      // als tweede asset. Loopt het budget over, dan is dat een getypte
      // fout en geen stille leegte.
      try {
        _storedPath = WebAssetStore.put(
          _wavBytes(_mixMem.takeBytes()),
          name: 'call.wav',
        );
        // De naam koppelt het manifest aan díe wav-sleutel, zodat de
        // transcriptiepass het bij `readCallSources(wavPad)` terugvindt.
        WebAssetStore.put(
          utf8.encode(_manifestJson()),
          name: '$_storedPath.sources.json',
        );
      } on WebAssetBudgetExceeded {
        throw const CapacityExceeded(
          'de opname past niet in het browsergeheugen',
        );
      }
    }
    if (!_ended.isClosed) await _ended.close();
    if (!_liveOut.isClosed) await _liveOut.close();
    final duration = mixWav?.duration ?? _emitted;
    return RecordedAudio(
      durablePath: _storedPath,
      duration: duration,
      kinds: {CaptureSourceKind.callAudio},
    );
  }

  /// De provenance: welke bronnen in welke file zitten, hoeveel frames
  /// ze leverden en hoeveel stilte-ticks hun gaten vulden. Geen
  /// sprekerlabels — de participantId is een roster-id, geen naam.
  String _manifestJson() {
    final sources = [
      for (final s in _srcs.values)
        {
          'file': _stagingDir != null ? s.fileName : null,
          'trackId': s.trackId,
          'role': s.role.name,
          'participantId': s.participantId,
          'frames': s.frames,
          'silenceTicks': s.silenceTicks,
          'firstFrameAt': s.firstAt.toIso8601String(),
          'lastFrameAt': s.lastFrameAt.toIso8601String(),
        },
    ];
    return jsonEncode({'version': 1, 'sources': sources});
  }

  /// Een complete WAV-header om de gemixte PCM heen (web-variant van
  /// `recording.wav`).
  static Uint8List _wavBytes(Uint8List pcm) {
    final out = Uint8List(44 + pcm.length);
    final v = ByteData.sublistView(out);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out[off + i] = s.codeUnitAt(i);
      }
    }

    str(0, 'RIFF');
    v.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    v.setUint32(16, 16, Endian.little);
    v.setUint16(20, 1, Endian.little);
    v.setUint16(22, recordingChannels, Endian.little);
    v.setUint32(24, recordingSampleRate, Endian.little);
    v.setUint32(28, recordingSampleRate * recordingChannels * 2, Endian.little);
    v.setUint16(32, recordingChannels * 2, Endian.little);
    v.setUint16(34, recordingBitsPerSample, Endian.little);
    str(36, 'data');
    v.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
  }
}
