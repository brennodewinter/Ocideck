import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/meetings/call_audio_capture_source.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/call_recording.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/state/call_recording_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/panels/call_panel.dart';
import 'package:ocideck/widgets/panels/call_recording_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_until.dart';
import 'fakes/fake_meeting_provider.dart';

const _wholeCall = CallAudioCaptureFact(localOutbound: true, remote: true);

/// Echte staging op schijf: de duurzame pipeline van #2529 schrijft echt,
/// dus de test laat hem ook echt schrijven — in een wegwerpbare tempmap.
class _Staging implements RecordingStaging {
  _Staging() {
    _root = Directory.systemTemp.createTempSync('callrec-test');
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

ProviderContainer _container() => ProviderContainer(
  overrides: [recordingStagingProvider.overrideWithValue(_Staging())],
);

/// Een lopende opname laat een echte mixer-ticktimer en open wav's achter;
/// de teardown rondt hem netjes af (echte IO — daarom hier en niet in de
/// fake zone van de test zelf).
void _tear(ProviderContainer container) {
  addTearDown(() async {
    final handle = container.read(recordingSessionProvider);
    if (handle != null) await handle.stop();
    container.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'rustfase: geen bron is uit, whole-call zonder melding vraagt toestemming',
    () {
      expect(
        restingCallRecordingPhase(
          connected: true,
          audio: unavailableCallAudio,
          noticeAcknowledged: true,
        ),
        CallRecordingPhase.uit,
      );
      expect(
        restingCallRecordingPhase(
          connected: true,
          audio: _wholeCall,
          noticeAcknowledged: false,
        ),
        CallRecordingPhase.toestemmingNodig,
      );
      expect(
        restingCallRecordingPhase(
          connected: false,
          audio: _wholeCall,
          noticeAcknowledged: true,
        ),
        CallRecordingPhase.uit,
      );
      expect(
        phaseAfterCallRecordingStart(CallRecordingPhase.klaar),
        CallRecordingPhase.bezig,
      );
      expect(
        phaseAfterCallRecordingStart(CallRecordingPhase.bezig),
        CallRecordingPhase.bezig,
      );
    },
  );

  test('een server krijgt pas bytes als de upload apart is toegestaan', () {
    expect(
      mayForwardCallAudioToServer(
        phase: CallRecordingPhase.bezig,
        asrServerChosen: true,
        asrUploadAllowed: false,
        wholeCall: true,
      ),
      isFalse,
    );
    expect(
      mayForwardCallAudioToServer(
        phase: CallRecordingPhase.bezig,
        asrServerChosen: true,
        asrUploadAllowed: true,
        wholeCall: true,
      ),
      isTrue,
    );
    expect(
      mayForwardCallAudioToServer(
        phase: CallRecordingPhase.klaar,
        asrServerChosen: true,
        asrUploadAllowed: true,
        wholeCall: true,
      ),
      isFalse,
    );
  });

  testWidgets('een actieve call zonder audiobron toont de reden, geen start', (
    tester,
  ) async {
    final container = _container();
    _tear(container);
    final session = await _join(container);
    await tester.pumpWidget(_panel(container));
    await tester.pump();

    expect(find.text('Opnemen en transcriberen'), findsOneWidget);
    expect(find.textContaining('geen aparte audiobron'), findsOneWidget);
    expect(find.text('Start opname'), findsNothing);

    await tester.tap(find.byTooltip('Dempen opheffen'));
    await tester.pump();
    session.setRecording(active: true);
    await tester.pump();

    expect(session.captureStarts, 0);
    expect(find.textContaining('niet de opname van OciDeck'), findsOneWidget);
    expect(container.read(callRecordingProvider).phase, CallRecordingPhase.uit);
  });

  testWidgets('deelnemen toont de knop niet, en een verboden beleid ook niet', (
    tester,
  ) async {
    final container = _container();
    _tear(container);
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    expect(find.text('Opnemen en transcriberen'), findsNothing);

    final session = await _join(container);
    session.setCapabilities(
      const MeetingCapabilities(
        audio: true,
        callAudio: CallAudioCaptureFact(
          localOutbound: true,
          remote: true,
          denial: CallAudioDenial.providerForbids,
        ),
      ),
    );
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    expect(find.textContaining('staat opnemen niet toe'), findsOneWidget);
    expect(find.text('Start opname'), findsNothing);
    expect(session.captureStarts, 0);
  });

  testWidgets(
    'start vraagt een bewuste bevestiging en een tweede start niets',
    (tester) async {
      final container = _container();
      _tear(container);
      final session = await _join(container);
      session.captureController = StreamController<CallAudioChunk>.broadcast();
      session.setCapabilities(
        const MeetingCapabilities(audio: true, callAudio: _wholeCall),
      );
      await tester.pumpWidget(_panel(container));
      await tester.pump();

      expect(find.text('Start opname'), findsNothing);
      await tester.tap(find.text('Deelnemers zijn geïnformeerd'));
      await tester.pump();

      final start = find.text('Start opname');
      expect(start, findsOneWidget);
      Focus.of(tester.element(start)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      // De duurzame pipeline doet echte IO (stagingmap, wav-files) — die
      // komt terug in de echte eventloop-stappen van pumpUntil; de pumps
      // ertussen spoelen de fake-zone-voortzettingen erachteraan door.
      unawaited(container.read(callRecordingProvider.notifier).start());
      await pumpUntil(
        tester,
        () => session.captureStarts == 1,
        reason: 'de opname startte niet',
      );

      expect(session.captureStarts, 1);
      expect(find.text('Start opname'), findsNothing);
      expect(
        find.textContaining('OciDeck neemt deze vergadering op'),
        findsWidgets,
      );
      expect(
        container.read(callRecordingProvider).phase,
        CallRecordingPhase.bezig,
      );

      // De lopende opname opruimen: zijn drain-timer is anders een
      // hangende fake-timer aan het einde van de test.
      unawaited(container.read(recordingSessionProvider)?.stop());
      await pumpUntil(
        tester,
        () => container.read(recordingSessionProvider) == null,
        reason: 'de opname stopte niet',
      );
    },
  );

  testWidgets('zonder uploadtoestemming verlaat geen brok de server', (
    tester,
  ) async {
    final container = _container();
    _tear(container);
    final session = await _join(container);
    session.setCapabilities(
      const MeetingCapabilities(audio: true, callAudio: _wholeCall),
    );
    await container
        .read(asrServerProfileProvider.notifier)
        .set(
          const AsrServerProfile(
            enabled: true,
            mode: AsrServerMode.loopback,
            baseUrl: 'http://127.0.0.1:8080',
          ),
        );
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    await tester.tap(find.text('Deelnemers zijn geïnformeerd'));
    await tester.pump();
    // De start gaat hier via de notifier: het knoppad is elders bewezen,
    // deze toets gaat om het uploadhek.
    session.captureController = StreamController<CallAudioChunk>.broadcast();
    unawaited(container.read(callRecordingProvider.notifier).start());
    await pumpUntil(
      tester,
      () => session.captureStarts == 1,
      reason: 'de opname startte niet',
    );

    // De mixer pace't op `clock.now()` — in de testzone is dat de
    // fake-klok. pumpUntil verloopt die per stap én geeft de echte
    // eventloop tijd voor de drain en de wav-IO.
    session.captureController!.add(_chunk());
    await pumpUntil(
      tester,
      () => container.read(callRecordingProvider).capturedChunks == 1,
      reason: 'de mixer emiteerde geen tick',
    );
    expect(container.read(callRecordingProvider).forwardedChunks, 0);
    await tester.pump();
    expect(find.textContaining('tot je dat apart toestaat'), findsOneWidget);

    container.read(callRecordingProvider.notifier).setAsrUploadAllowed(true);
    await tester.pump();
    session.captureController!.add(_chunk());
    await pumpUntil(
      tester,
      () => container.read(callRecordingProvider).capturedChunks == 2,
      reason: 'de mixer emiteerde geen tweede tick',
    );
    expect(container.read(callRecordingProvider).forwardedChunks, 1);

    container.read(callRecordingProvider.notifier).setAsrUploadAllowed(false);
    await tester.pump();
    session.captureController!.add(_chunk());
    await pumpUntil(
      tester,
      () => container.read(callRecordingProvider).capturedChunks == 3,
      reason: 'de mixer emiteerde geen derde tick',
    );
    expect(container.read(callRecordingProvider).forwardedChunks, 1);
    expect(session.connectionState, MeetingConnectionState.connected);

    unawaited(container.read(recordingSessionProvider)?.stop());
    await pumpUntil(
      tester,
      () => container.read(recordingSessionProvider) == null,
      reason: 'de opname stopte niet',
    );
  });

  testWidgets('de module aanzetten start niets; uitzetten stopt de opname', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      transcriptionModuleEnabledKey: true,
    });
    final container = _container();
    _tear(container);
    final session = await _ready(container);
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    await container.read(transcriptionModuleProvider.notifier).setEnabled(true);
    await tester.pump();
    expect(session.captureStarts, 0);

    await tester.tap(find.text('Deelnemers zijn geïnformeerd'));
    await tester.pump();
    await tester.tap(find.text('Start opname'));
    await pumpUntil(
      tester,
      () => session.captureStarts == 1,
      reason: 'de opname startte niet',
    );
    expect(session.captureStarts, 1);

    unawaited(
      container.read(transcriptionModuleProvider.notifier).setEnabled(false),
    );
    await pumpUntil(
      tester,
      () => session.captureStops == 1,
      reason: 'de opname stopte niet',
    );
    await tester.pump();
    expect(session.captureStops, 1);
    expect(
      container.read(callRecordingProvider).phase,
      isNot(CallRecordingPhase.bezig),
    );
  });

  testWidgets('de strook blijft als het paneel weg is', (tester) async {
    final container = _container();
    _tear(container);
    final session = await _ready(container);
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    await tester.tap(find.text('Deelnemers zijn geïnformeerd'));
    await tester.pump();
    await tester.tap(find.text('Start opname'));
    await pumpUntil(
      tester,
      () => session.captureStarts == 1,
      reason: 'de opname startte niet',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CallRecordingBanner())),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('OciDeck neemt deze vergadering op'),
      findsOneWidget,
    );
    expect(find.text('Stoppen'), findsOneWidget);
    expect(session.left, isFalse);

    await tester.tap(find.text('Stoppen'));
    await pumpUntil(
      tester,
      () => find.text('Stoppen').evaluate().isEmpty,
      reason: 'de Stop-knop verdween niet',
    );
    expect(find.text('Stoppen'), findsNothing);
    expect(session.connectionState, MeetingConnectionState.connected);
  });

  testWidgets('een whole-call-claim zonder tap faalt en verlaat de call niet', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = _container();
    _tear(container);
    final session = await _join(container);
    session.setCapabilities(
      const MeetingCapabilities(audio: true, callAudio: _wholeCall),
    );
    await tester.pumpWidget(_panel(container));
    await tester.pump();
    await tester.tap(find.text('Deelnemers zijn geïnformeerd'));
    await tester.pump();
    await tester.tap(find.text('Start opname'));
    await pumpUntil(
      tester,
      () =>
          container.read(callRecordingProvider).phase ==
          CallRecordingPhase.fout,
      reason: 'de fase werd niet fout',
    );
    await tester.pump();

    try {
      expect(
        find.textContaining('Je zit nog in de vergadering'),
        findsOneWidget,
      );
      expect(container.read(callRecordingProvider).forwardedChunks, 0);
      expect(session.left, isFalse);
      expect(
        find.bySemanticsLabel(RegExp('Je zit nog in de vergadering')),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });
}

Widget _panel(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(body: SizedBox(width: 360, child: CallPanel())),
  ),
);

Future<FakeMeetingSession> _join(ProviderContainer container) async {
  const provider = FakeMeetingProvider();
  final match = provider.match(Uri.parse('https://fake.local/r'))!;
  final session = await provider.join(
    MeetingJoinRequest(link: match, displayName: 'Me'),
  );
  container.read(meetingSessionProvider.notifier).adopt(session);
  return session as FakeMeetingSession;
}

Future<FakeMeetingSession> _ready(ProviderContainer container) async {
  final session = await _join(container);
  session.captureController = StreamController<CallAudioChunk>.broadcast();
  session.setCapabilities(
    const MeetingCapabilities(audio: true, callAudio: _wholeCall),
  );
  return session;
}

var _chunkSeq = 0;

/// Eén brok van precies één mix-tick — de duurzame pipeline van #2529
/// telt geëmitteerde ticks, geen binnenkomende brokken.
CallAudioChunk _chunk() => CallAudioChunk(
  participantId: 'zij',
  role: CallAudioRole.remote,
  trackId: 'zij-audio',
  // De poort dedupt één bron op hetzelfde tijdstip — elk brok moet dus
  // een echt later tijdstip hebben, zoals een echte tap die levert.
  at: DateTime.utc(2026, 10, 25, 22).add(Duration(seconds: _chunkSeq++)),
  pcm: Uint8List(callAudioTickBytes),
  sampleRateHz: 16000,
);
