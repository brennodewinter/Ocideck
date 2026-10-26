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
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
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

  test('het manifest telt eerlijk welke bronnen stilte bijdroegen', () {
    // Geen manifest of een vreemde vorm is geen claim over gaten.
    expect(missingCallAudio(null), isNull);
    expect(missingCallAudio(const {}), isNull);
    expect(missingCallAudio(const {'sources': 'x'}), isNull);
    expect(
      missingCallAudio(const {
        'version': 1,
        'sources': [
          {'silenceTicks': 0},
        ],
      }),
      isNull,
    );
    // Twee bronnen met gaten — geteld én gesommeerd (een tick is 20 ms).
    final gaps = missingCallAudio(const {
      'version': 1,
      'sources': [
        {'silenceTicks': 50},
        {'silenceTicks': 100},
        {'silenceTicks': 0},
      ],
    });
    expect(gaps, isNotNull);
    expect(gaps!.$1, 2);
    expect(gaps.$2, const Duration(milliseconds: 3000));
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

  testWidgets('zonder sessieconsent is er geen live-route en gaat niets weg', (
    tester,
  ) async {
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
    // Geen host gebonden, geen live-serverstatus — de voorlopige route
    // staat uit terwijl de duurzame opname gewoon doortelt.
    expect(
      container.read(recordingSessionProvider.notifier).liveSessionHost,
      isNull,
    );
    expect(container.read(liveServerStatusProvider), LiveServerStatus.off);
    expect(session.connectionState, MeetingConnectionState.connected);

    unawaited(container.read(recordingSessionProvider)?.stop());
    await pumpUntil(
      tester,
      () => container.read(recordingSessionProvider) == null,
      reason: 'de opname stopte niet',
    );
  });

  testWidgets(
    'met sessieconsent benoemt de sessie de host; zonder endpoint wordt '
    'de route eerlijk lost en loopt de opname door',
    (tester) async {
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
      session.captureController = StreamController<CallAudioChunk>.broadcast();
      // De consent van een opt-in die "127.0.0.1" benoemde — zónder live-
      // endpoint in het profiel faalt de stream op de consent-check; dat
      // is de eerlijke `lost`, geen socket en geen stille afwezigheid.
      unawaited(
        container
            .read(callRecordingProvider.notifier)
            .start(liveConsent: const ServerConsent.liveSession('127.0.0.1')),
      );
      await pumpUntil(
        tester,
        () => session.captureStarts == 1,
        reason: 'de opname startte niet',
      );

      // De consent bereikte de sessieprovider: de host is gebonden.
      expect(
        container.read(recordingSessionProvider.notifier).liveSessionHost,
        '127.0.0.1',
      );
      // De route faalde op de consent-check — `lost`, en de opname telt
      // door: de live-route is los van de duurzame pipeline.
      await pumpUntil(
        tester,
        () => container.read(liveServerStatusProvider) == LiveServerStatus.lost,
        reason: 'de live-route werd niet als verloren gemeld',
      );
      session.captureController!.add(_chunk());
      await pumpUntil(
        tester,
        () => container.read(callRecordingProvider).capturedChunks == 1,
        reason: 'de mixer emiteerde geen tick na de live-breuk',
      );
      expect(
        container.read(callRecordingProvider).phase,
        CallRecordingPhase.bezig,
      );

      unawaited(container.read(recordingSessionProvider)?.stop());
      await pumpUntil(
        tester,
        () => container.read(recordingSessionProvider) == null,
        reason: 'de opname stopte niet',
      );
    },
  );

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
      expect(container.read(callRecordingProvider).capturedChunks, 0);
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
