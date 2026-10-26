// De live-sessieketen van #2525 over de echte providerlaag: een
// loopback-WebSocket als "server", een fake capture als bron — de
// consent, LivePass, engine, voorlopige tekst, verbindingsstatus en
// expliciete herstelknop zijn dan aantoonbaar zonder een echt apparaat.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/state/transcription_provider.dart';

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

/// Wacht tot [condition] waar is — events lopen over echte sockets en
/// microtasks, dus poll i.p.v. één pump.
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
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
