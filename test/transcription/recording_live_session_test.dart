// De live-sessieketen van #2525 over de echte providerlaag: een
// loopback-WebSocket als "server", een fake capture als bron — de
// consent, LivePass, engine, voorlopige tekst, verbindingsstatus en
// expliciete herstelknop zijn dan aantoonbaar zonder een echt apparaat.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_capture_source.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/state/call_recording_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';

import '../meetings/fakes/fake_meeting_provider.dart';
import 'fakes/fake_capture_source.dart';

class _Staging implements RecordingStaging {
  @override
  Future<String?> createSessionDir() async => '/tmp/ocideck-live-test';

  @override
  Future<void> discardDir(String? dir) async {}

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

class _Profile extends AsrServerProfileNotifier {
  _Profile(this.profile);

  final AsrServerProfile profile;

  @override
  AsrServerProfile build() => profile;
}

/// Een loopback-WS die elk inkomend frame bevestigt met een partial —
/// het `vosk-ws-1`-protocol in het klein.
class LiveStubServer {
  final frames = <dynamic>[];
  final firstBinaryFrame = Completer<void>();
  HttpServer? _http;
  final wsConnections = <WebSocket>[];

  int get port => _http!.port;

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      _http!.forEach((req) async {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          wsConnections.add(ws);
          ws.listen((frame) {
            frames.add(frame);
            if (frame is List<int> &&
                frame.isNotEmpty &&
                !firstBinaryFrame.isCompleted) {
              firstBinaryFrame.complete();
            }
            ws.add('{"partial":"hal"}');
          });
        }
      }),
    );
  }

  /// Hang de kant van de server op — zo breekt de live-route zonder
  /// dat de opname iets merkt.
  Future<void> hangUp() async {
    for (final ws in wsConnections) {
      await ws.close();
    }
  }

  Future<void> close() async {
    await _http?.close(force: true);
    _http = null;
  }
}

AsrServerProfile liveProfile(int port) => AsrServerProfile(
  enabled: true,
  mode: AsrServerMode.loopback,
  baseUrl: 'http://127.0.0.1:8080',
  liveUrl: 'ws://127.0.0.1:$port',
);

ProviderContainer containerFor(AsrServerProfile profile) => ProviderContainer(
  overrides: [
    recordingStagingProvider.overrideWithValue(_Staging()),
    asrServerProfileProvider.overrideWith(() => _Profile(profile)),
  ],
);

/// De callopname schrijft écht naar schijf (#2529) — zijn staging moet
/// dus een echte map zijn, anders zou de wav-open de test op iets anders
/// laten falen dan wat hij bewijst.
class _DirStaging implements RecordingStaging {
  _DirStaging() {
    _root = Directory.systemTemp.createTempSync('calllive-test');
    addTearDown(() async {
      if (await _root.exists()) await _root.delete(recursive: true);
    });
  }

  late final Directory _root;
  var _n = 0;

  @override
  Future<String?> createSessionDir() async {
    final dir = Directory('${_root.path}/s${_n++}');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<void> discardDir(String? dir) async {
    if (dir == null) return;
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

/// Een verbonden fake-call met een whole-call-claim én de tap die hem
/// waarmaakt — de bron van `CallAudioCaptureSource`.
Future<FakeMeetingSession> _joinFakeCall() async {
  const provider = FakeMeetingProvider();
  final match = provider.match(Uri.parse('https://fake.local/r'))!;
  final session =
      await provider.join(MeetingJoinRequest(link: match, displayName: 'Me'))
          as FakeMeetingSession;
  session.captureController = StreamController<CallAudioChunk>.broadcast();
  session.setCapabilities(
    const MeetingCapabilities(
      audio: true,
      callAudio: CallAudioCaptureFact(localOutbound: true, remote: true),
    ),
  );
  return session;
}

var _callSeq = 0;

/// Eén remote brok van precies één mix-tick (640 B 16 kHz mono).
CallAudioChunk _callChunk() => CallAudioChunk(
  participantId: 'zij',
  role: CallAudioRole.remote,
  trackId: 'zij-audio',
  at: DateTime.now().add(Duration(seconds: _callSeq++)),
  pcm: Uint8List(callAudioTickBytes),
  sampleRateHz: 16000,
);

/// Wacht tot [condition] waar is — events lopen over echte sockets en
/// microtasks, dus poll i.p.v. één pump.
Future<void> until(bool Function() condition) async {
  // Een belaste CI-run kan socket, mixer en WAV-schrijver meer dan 1 s kosten.
  for (var i = 0; i < 5000 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'voorwaarde niet bereikt');
}

Future<FakeCaptureSource> startMic(
  ProviderContainer c, {
  ServerConsent? liveConsent,
}) async {
  final source = FakeCaptureSource();
  await c
      .read(recordingSessionProvider.notifier)
      .start(
        source,
        kinds: const {CaptureSourceKind.microphone},
        consent: const RecordingConsent(participantNoticeAcknowledged: true),
        liveConsent: liveConsent,
      );
  return source;
}

void main() {
  // Geen binding: deze test draait alleen providers en échte loopback-
  // sockets — TestWidgetsFlutterBinding zou de HttpClient mocken en de
  // WebSocket-upgrade onmogelijk maken.
  test('zonder sessieconsent geen live-route en status off', () async {
    final c = containerFor(liveProfile(1));
    addTearDown(c.dispose);
    await startMic(c);
    expect(c.read(liveServerStatusProvider), LiveServerStatus.off);
    await c
        .read(recordingSessionProvider.notifier)
        .stopAll(RecordingEndReason.userStop);
  });

  test('met consent stroomt de chunk de socket op en de tekst terug', () async {
    final server = LiveStubServer();
    await server.start();
    addTearDown(server.close);
    final c = containerFor(liveProfile(server.port));
    addTearDown(c.dispose);

    final source = await startMic(
      c,
      liveConsent: const ServerConsent.liveSession('127.0.0.1'),
    );
    // De engine opent de socket, stuurt zijn config-frame, en de
    // eerste partial terug zet de status op live.
    await until(
      () => c.read(liveServerStatusProvider) == LiveServerStatus.live,
    );
    expect(server.frames, isNotEmpty);

    // De capture levert een blok — het verlaat als binair frame en de
    // partial komt als voorlopige tekst terug. Wacht op het frame zelf:
    // de config-echo zette de tekst namelijk al.
    source.lastSession!.emitChunk([1, 2, 3], const Duration(seconds: 1));
    await until(
      () => server.frames.any(
        (f) => f is List<int> && f.length == 3 && f[0] == 1,
      ),
    );
    expect(c.read(provisionalCaptionProvider).text, 'hal');
    expect(
      c.read(recordingSessionProvider.notifier).liveSessionHost,
      '127.0.0.1',
    );

    await c
        .read(recordingSessionProvider.notifier)
        .stopAll(RecordingEndReason.userStop);
    expect(c.read(liveServerStatusProvider), LiveServerStatus.off);
  });

  test('callaudio met consent: de mix-tick bereikt de socket, de partial komt '
      'terug (#2530)', () async {
    final server = LiveStubServer();
    await server.start();
    addTearDown(server.close);
    final c = ProviderContainer(
      overrides: [
        recordingStagingProvider.overrideWithValue(_DirStaging()),
        asrServerProfileProvider.overrideWith(
          () => _Profile(liveProfile(server.port)),
        ),
      ],
    );
    addTearDown(c.dispose);

    // De echte call-flow: de opt-in benoemde de host, de Start-knop gaf
    // die als sessieconsent door aan de call-notifier.
    final session = await _joinFakeCall();
    final notifier = c.read(callRecordingProvider.notifier)..bind(session);
    notifier.setNotice(true);
    final liveReady = Completer<void>();
    final statusSubscription = c.listen(liveServerStatusProvider, (_, next) {
      if (next == LiveServerStatus.live && !liveReady.isCompleted) {
        liveReady.complete();
      }
    });
    addTearDown(statusSubscription.close);
    final partialReady = Completer<void>();
    final partialSubscription = c.listen(provisionalCaptionProvider, (_, next) {
      if (next.text.isNotEmpty && !partialReady.isCompleted) {
        partialReady.complete();
      }
    });
    addTearDown(partialSubscription.close);
    await notifier.start(
      liveConsent: const ServerConsent.liveSession('127.0.0.1'),
    );
    await liveReady.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TestFailure(
        'callaudio-verbinding bleef ${c.read(liveServerStatusProvider)}; '
        'captureStarts=${session.captureStarts}, frames=${server.frames.length}',
      ),
    );
    expect(session.captureStarts, 1);

    // Eén remote brok → de mixer emiteert een 20 ms-tick → die gaat als
    // binair frame de socket op, zijn echo komt als voorlopige tekst terug.
    final tickSeen = Completer<void>();
    final tickSubscription = c.listen(callRecordingProvider, (_, next) {
      if (next.capturedChunks > 0 && !tickSeen.isCompleted) tickSeen.complete();
    });
    addTearDown(tickSubscription.close);
    session.captureController!.add(_callChunk());
    await Future.wait([
      server.firstBinaryFrame.future,
      tickSeen.future,
      partialReady.future,
    ]).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TestFailure(
        'callaudio-mix ontbrak: '
        'frames=${server.frames.map((f) => f.runtimeType).toList()}, '
        'ticks=${c.read(callRecordingProvider).capturedChunks}, '
        'fase=${c.read(callRecordingProvider).phase}, '
        'live=${c.read(liveServerStatusProvider)}',
      ),
    );
    expect(c.read(provisionalCaptionProvider).text, 'hal');

    await notifier.stop();
    expect(c.read(liveServerStatusProvider), LiveServerStatus.off);
  });

  test('callaudio zonder consent: geen socket en geen bytes — wel een duurzame '
      'wav (#2530)', () async {
    final server = LiveStubServer();
    await server.start();
    addTearDown(server.close);
    // Het profiel hééft een live-endpoint — zonder sessieconsent mag het
    // toch nooit benaderd worden. "Opnemen en later transcriberen" blijft
    // werken.
    final c = ProviderContainer(
      overrides: [
        recordingStagingProvider.overrideWithValue(_DirStaging()),
        asrServerProfileProvider.overrideWith(
          () => _Profile(liveProfile(server.port)),
        ),
      ],
    );
    addTearDown(c.dispose);

    final session = await _joinFakeCall();
    final notifier = c.read(callRecordingProvider.notifier)..bind(session);
    notifier.setNotice(true);
    await notifier.start();

    session.captureController!.add(_callChunk());
    await until(() => c.read(callRecordingProvider).capturedChunks > 0);
    expect(server.wsConnections, isEmpty);
    expect(c.read(liveServerStatusProvider), LiveServerStatus.off);
    expect(c.read(recordingSessionProvider.notifier).liveSessionHost, isNull);

    // De duurzame mix staat op schijf — later transcriberen kan.
    final stagingDir = c.read(recordingSessionProvider)!.stagingDir!;
    await notifier.stop();
    final wav = File('$stagingDir/recording.wav');
    expect(await wav.exists(), isTrue);
    expect(await wav.length(), greaterThan(44));
    expect(await File('$stagingDir/sources.json').exists(), isTrue);
  });

  test(
    'serverbreuk zet status lost — de opname loopt door; herstel is expliciet',
    () async {
      final server = LiveStubServer();
      await server.start();
      addTearDown(server.close);
      final c = containerFor(liveProfile(server.port));
      addTearDown(c.dispose);

      final notifier = c.read(recordingSessionProvider.notifier);
      await startMic(
        c,
        liveConsent: const ServerConsent.liveSession('127.0.0.1'),
      );
      await until(
        () => c.read(liveServerStatusProvider) == LiveServerStatus.live,
      );

      // De server hangt op: de opname blijft staan, alleen de live-route
      // verliest zijn status.
      await server.hangUp();
      await until(
        () => c.read(liveServerStatusProvider) == LiveServerStatus.lost,
      );
      expect(c.read(recordingSessionProvider), isNotNull);

      // Expliciet herstel (de knop die de host opnieuw noemde) bouwt een
      // nieuwe socket — geen stille reconnect maar een tweede handshake.
      final connections = server.wsConnections.length;
      await notifier.reconnectLive(
        const ServerConsent.liveSession('127.0.0.1'),
      );
      await until(() => server.wsConnections.length > connections);
      await until(
        () => c.read(liveServerStatusProvider) == LiveServerStatus.live,
      );

      await notifier.stopAll(RecordingEndReason.userStop);
    },
  );
}
