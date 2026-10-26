// De live-serverengine (docs/design/TRANSCRIPTION.md §4.3, #2525):
// een `liveServer`-engine die de lopende opname als PCM-frames naar
// het `liveUrl`-endpoint streamt (protocol `vosk-ws-1`) en voorlopige
// tekst teruglevert.
//
// Dezelfde harde regels als de batch-engine, plus twee eigen:
//  * niets vertrekt zonder de egresspoort én een **sessie**-consent
//    ([ServerConsent.liveSession]) die exact díe host benoemt — een
//    per-taakconsent voor een upload dekt geen livestream, en andersom;
//  * geen stil hervatten: breekt de socket, dan eindigt de stream met
//    [ServerRefused]. Een nieuwe sessie is een nieuwe zichtbare keuze —
//    dit ding kent bewust geen reconnect-logica.
//
// De engine is zuiver Dart: socket en audiolezer worden geïnjecteerd,
// zodat elke regel hier op de VM te toetsen is.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../models/asr_server_profile.dart';
import 'asr_live_protocol.dart';
import 'asr_live_transport.dart';
import 'asr_server_engine.dart'
    show AsrAudioReader, AsrProbeStatus, AsrServerProbe;
import 'asr_server_gate.dart';
import 'capture_source.dart' show AudioChunk;
import 'transcription_engine.dart';
import 'transcription_errors.dart';

/// De samplerate die onze capture-pipeline levert én het protocol
/// spreekt — 16 kHz mono s16le, zie `desktop_mic_source`.
const liveSampleRate = 16000;

/// Framegrootte voor de definitieve pass: 64 KiB ≈ 2 s audio per stuk.
const _definitiveFrameBytes = 64 * 1024;

/// Maximale zendpauze per frame in de definitieve pass. dart:io's en de
/// browser-WebSocket kennen geen `bufferedAmount` dat de engine kan
/// afdwingen; de echte backpressure is dus tempo — ~13 MB/s is ruim
/// boven elke ASR-behoefte en begrenst wat er in buffers kan groeien.
// ponytail: echte bufferedAmount-backpressure bestaat niet op deze
// transports; upgrade-pad is een transport met een flush/buffer-API zodra
// er één landt.
const _definitiveFramePace = Duration(milliseconds: 5);

/// Hoe lang we na `{"eof" : 1}` nog op eindresultaten wachten voor we de
/// socket zelf sluiten — een server die niet sluit mag een sessie niet
/// eeuwig vasthouden.
const _eofGrace = Duration(seconds: 10);

/// De live-engine voor een serverprofiel. [cancel] breekt een lopende
/// verbinding af — de toekomst voltooit met [Cancelled].
class AsrLiveServerEngine implements TranscriptionEngine {
  AsrLiveServerEngine({
    required this.profile,
    required this.transport,
    required this.audioReader,
    Future<String?> Function()? apiKeyReader,
    bool? isWeb,
  }) : _apiKeyReader = apiKeyReader ?? (() async => null),
       _isWeb = isWeb ?? kIsWeb;

  /// Het injecteerbare transport — de enige plek die het netwerk op gaat.
  final AsrLiveTransport transport;

  final AsrServerProfile profile;

  /// Leest de API-sleutel van dit profiel — per verbinding, zodat een
  /// vervangen sleutel meteen geldt. Op io gaat hij in de `Authorization`-
  /// header van de handshake; op web kan een WebSocket geen headers
  /// zetten (gedocumenteerde grens, nooit de URL).
  final Future<String?> Function() _apiKeyReader;

  /// Leest de bytes achter een `AudioRef` voor de definitieve pass.
  final AsrAudioReader audioReader;
  final bool _isWeb;

  AsrLiveSocket? _socket;
  var _cancelled = false;

  @override
  EngineKind get kind => EngineKind.liveServer;

  @override
  Future<EngineCapabilities> capabilities() async {
    return const EngineCapabilities(
      // `words:true` levert woordtijden; taal en diarizatie zijn een
      // servereigenschap die we niet raden (§2.4).
      streaming: true,
      timestamps: true,
    );
  }

  /// De poortuitslag voor het live-endpoint — zodat de UI kan uitleggen
  /// waarom live niet kan vóór er iets start. Geen netwerk, geen audio.
  AsrGateDecision gateLive() =>
      AsrServerGate.evaluateLive(profile, isWeb: _isWeb);

  /// De capability-proef die #2525 eist voordat live aangeboden wordt:
  /// open de socket, stuur config + eof, en bewijs dat het antwoord de
  /// `vosk-ws-1`-vorm heeft. Er gaat géén gebruikersaudio mee — alleen
  /// het protocolframe. Een endpoint dat wel WS accepteert maar het
  /// protocol niet spreekt is `unreachable`, niet "live".
  Future<AsrServerProbe> probeLive() async {
    final decision = gateLive();
    if (decision is! AsrGateAllow) {
      final reason = decision is AsrGateDeny ? decision.reason.name : '?';
      return AsrServerProbe(status: AsrProbeStatus.refused, detail: reason);
    }
    AsrLiveSocket? socket;
    try {
      socket = await transport.connect(
        url: decision.uri,
        strategy: decision.strategy,
        headers: await _headers(),
      );
      socket.sendText(buildLiveConfigFrame(sampleRate: liveSampleRate));
      socket.sendText(liveEofFrame);
      final first = await socket.messages.first.timeout(
        const Duration(seconds: 10),
      );
      if (first is String && parseLiveMessage(first) is! LiveUnknown) {
        return const AsrServerProbe(
          status: AsrProbeStatus.reachable,
          detail: liveProtocolId,
        );
      }
      return const AsrServerProbe(
        status: AsrProbeStatus.unreachable,
        detail: 'endpoint spreekt geen $liveProtocolId',
      );
    } on AsrLiveException catch (e) {
      return AsrServerProbe(
        status: AsrProbeStatus.unreachable,
        detail: e.message,
      );
    } on TimeoutException {
      return const AsrServerProbe(
        status: AsrProbeStatus.unreachable,
        detail: 'geen protocolantwoord',
      );
    } finally {
      await socket?.close();
    }
  }

  @override
  Stream<PartialTranscript>? transcribeLive(
    Stream<AudioChunk> chunks, {
    TranscriptionOptions? options,
  }) {
    // De sessieconsent benoemt host én bereik — een per-taakconsent
    // geldt hier niet (die dekt één bestand, geen stream).
    final consent = options?.serverConsent;
    if (consent == null ||
        !consent.sessionScope ||
        consent.host != profile.liveHost) {
      return Stream.error(
        const ConsentRequired('livesessie niet bevestigd voor deze host'),
      );
    }
    final decision = gateLive();
    if (decision is! AsrGateAllow) {
      return Stream.error(_gateError(decision));
    }

    final controller = StreamController<PartialTranscript>();
    var lastOffset = Duration.zero;
    var sentEof = false;
    StreamSubscription<AudioChunk>? chunkSub;
    StreamSubscription<Object>? inboundSub;
    Timer? eofTimer;

    Future<void> teardown() async {
      eofTimer?.cancel();
      await chunkSub?.cancel();
      await inboundSub?.cancel();
      final socket = _socket;
      _socket = null;
      await socket?.close();
    }

    void finishError(Object error) {
      unawaited(teardown());
      if (!controller.isClosed) {
        controller.addError(error);
        unawaited(controller.close());
      }
    }

    () async {
      final AsrLiveSocket socket;
      try {
        socket = await transport.connect(
          url: decision.uri,
          strategy: decision.strategy,
          headers: await _headers(),
        );
      } on Object {
        finishError(const ServerRefused('live-verbinding mislukt'));
        return;
      }
      if (_cancelled || controller.isClosed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.sendText(buildLiveConfigFrame(sampleRate: liveSampleRate));

      inboundSub = socket.messages.listen(
        (frame) {
          if (frame is! String || controller.isClosed) return;
          switch (parseLiveMessage(frame)) {
            case LivePartial(:final text):
              controller.add(PartialTranscript(text: text, offset: lastOffset));
            case LiveResult(:final text, :final words):
              controller.add(
                PartialTranscript(
                  text: text,
                  offset: words.isNotEmpty ? words.first.start : lastOffset,
                ),
              );
            case LiveUnknown():
              break; // externe invoer die we niet kennen — negeren
          }
        },
        onError: (Object e) {
          finishError(const ServerRefused('live-verbinding verbroken'));
        },
        onDone: () {
          // Voor `eof` gesloten = de server hing de sessie op.
          final error = sentEof
              ? null
              : const ServerRefused('server sloot de livesessie');
          unawaited(teardown());
          if (!controller.isClosed) {
            if (error != null) controller.addError(error);
            unawaited(controller.close());
          }
        },
      );

      chunkSub = chunks.listen(
        (chunk) {
          lastOffset = chunk.offset;
          socket.sendBytes(chunk.bytes);
        },
        onDone: () {
          sentEof = true;
          socket.sendText(liveEofFrame);
          // De server levert zijn laatste resultaat en sluit; sluit hij
          // niet binnen de coulance, dan is de sessie toch voorbij.
          eofTimer = Timer(_eofGrace, () {
            unawaited(teardown());
            if (!controller.isClosed) unawaited(controller.close());
          });
        },
        onError: (Object e) {
          finishError(const ServerRefused('audiostroom viel weg'));
        },
      );
    }();

    controller.onCancel = () {
      _cancelled = true;
      unawaited(teardown());
    };
    return controller.stream;
  }

  /// De definitieve pass over een voltooide opname: dezelfde socket en
  /// hetzelfde protocol, maar dan over de bewaarde file. Per-taakconsent
  /// (host + bestand) of de lopende sessieconsent geldt — beide benoemen
  /// díe host.
  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    final consent = options.serverConsent;
    final consentOk =
        consent != null &&
        consent.host == profile.liveHost &&
        (consent.sessionScope || consent.audioPath == audio.path);
    if (!consentOk) {
      throw const ConsentRequired('serververwerking niet bevestigd');
    }
    final decision = gateLive();
    if (decision is! AsrGateAllow) throw _gateError(decision);

    final bytes = await audioReader(audio.path);
    final pcm = wavPcmData(bytes);
    if (pcm == null) {
      throw const DecodeFailed('audio is geen leesbare WAV');
    }

    final socket = await _connectOrThrow(decision);
    final segments = <TranscriptSegment>[];
    final done = Completer<void>();
    final inboundSub = socket.messages.listen(
      (frame) {
        if (frame is! String) return;
        switch (parseLiveMessage(frame)) {
          case LiveResult(:final text, :final words):
            if (text.trim().isNotEmpty) {
              segments.add(
                TranscriptSegment(
                  text: text,
                  start: words.isNotEmpty ? words.first.start : null,
                ),
              );
            }
          case LivePartial() || LiveUnknown():
            break;
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    try {
      socket.sendText(buildLiveConfigFrame(sampleRate: liveSampleRate));
      for (var off = 0; off < pcm.length; off += _definitiveFrameBytes) {
        if (_cancelled) throw const Cancelled('verwerking afgebroken');
        final end = (off + _definitiveFrameBytes).clamp(0, pcm.length);
        socket.sendBytes(Uint8List.sublistView(pcm, off, end));
        options.onProgress?.call(end / pcm.length);
        // Geen bufferedAmount op deze transports — tempo is de grens.
        await Future<void>.delayed(_definitiveFramePace);
      }
      socket.sendText(liveEofFrame);
      await done.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw const ServerRefused('server sloot niet af'),
      );
      if (_cancelled) throw const Cancelled('verwerking afgebroken');
      return TranscriptResult(segments: segments);
    } on AsrLiveException catch (e) {
      throw ServerRefused(e.message);
    } finally {
      await inboundSub.cancel();
      if (identical(_socket, socket)) _socket = null;
      await socket.close();
      _cancelled = false;
    }
  }

  /// Breekt de lopende sessie of definitieve pass af; [transcribe]
  /// voltooit met [Cancelled], de livestream sluit.
  @override
  void cancel() {
    _cancelled = true;
    unawaited(_socket?.close());
  }

  TranscriptionError _gateError(AsrGateDecision decision) {
    final reason = decision is AsrGateDeny ? decision.reason : null;
    return switch (reason) {
      AsrGateDenial.disabled ||
      AsrGateDenial.modeNone ||
      AsrGateDenial.notConfigured => const EngineUnavailable(
        'live-endpoint niet bruikbaar',
      ),
      AsrGateDenial.cloudNotConfirmed => const ConsentRequired(
        'externe server niet bevestigd',
      ),
      _ => ServerRefused('egress geweigerd: ${reason?.name ?? '?'}'),
    };
  }

  Future<AsrLiveSocket> _connectOrThrow(AsrGateAllow allow) async {
    try {
      final socket = await transport.connect(
        url: allow.uri,
        strategy: allow.strategy,
        headers: await _headers(),
      );
      _socket = socket;
      return socket;
    } on Object {
      throw const ServerRefused('live-verbinding mislukt');
    }
  }

  Future<Map<String, String>> _headers() async {
    final key = (await _apiKeyReader())?.trim() ?? '';
    return {if (key.isNotEmpty) 'authorization': 'Bearer $key'};
  }
}
