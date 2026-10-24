// De sessiegrens uit #2510, getoetst aan de acceptatie: start alleen na
// een bewuste start mét toestemmingsbewijs, en élke eindweg — Stop,
// module uit, toestemming weg, bron weg, app dicht — breekt de capture
// aantoonbaar precies eenmaal af.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging_io.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

import 'fakes/fake_capture_source.dart';

void main() {
  late Directory tempDir;
  late RecordingManager manager;
  late FakeCaptureSource source;

  const consent = RecordingConsent(participantNoticeAcknowledged: true);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ocideck_rec_test');
    manager = RecordingManager(staging: IoRecordingStaging(baseDir: tempDir));
    source = FakeCaptureSource();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<RecordingHandle> startMic({RecordingConsent withConsent = consent}) =>
      manager.start(
        source,
        kinds: const {CaptureSourceKind.microphone},
        consent: withConsent,
      );

  test('start vereist een toestemmingsbewijs voor andermans stemmen', () {
    // systemAudio legt per constructie meer dan de eigen stem vast; zonder
    // bevestigde melding is ConsentRequired het gesloten antwoord (§2.3).
    expect(
      () => manager.start(
        source,
        kinds: const {CaptureSourceKind.systemAudio},
        consent: const RecordingConsent(participantNoticeAcknowledged: false),
      ),
      throwsA(isA<ConsentRequired>()),
    );
    expect(manager.active, isNull);
    expect(source.startCalls, 0);
  });

  test('microfoon mag starten zonder deelnemersmelding', () async {
    // Eigen stem alleen: de melding is een UI-keuze, geen poort.
    final handle = await startMic(
      withConsent: const RecordingConsent(participantNoticeAcknowledged: false),
    );
    expect(manager.active, same(handle));
    expect(handle.phase, RecordingPhase.recording);
    await handle.stop();
  });

  test('er is nooit meer dan één opname tegelijk', () async {
    await startMic();
    expect(() => startMic(), throwsA(isA<StateError>()));
    expect(source.startCalls, 1);
    await manager.stop(RecordingEndReason.userStop);
  });

  test('Stop rondt de capture af, eenmaal, met userStop als reden', () async {
    final handle = await startMic();
    final firstEvent = handle.events.first;

    await handle.stop();
    final event = await firstEvent;

    expect(source.lastSession!.stopCalls, 1);
    expect(handle.phase, RecordingPhase.ended);
    expect(handle.result!.durablePath, contains('opname.wav'));
    expect(manager.active, isNull);
    expect(event.phase, RecordingPhase.ended);
    expect(event.reason, RecordingEndReason.userStop);
  });

  test('bronverlies stopt de opname vanzelf, met sourceLost', () async {
    final handle = await startMic();
    final ended = Completer<RecordingEvent>();
    handle.events.listen((e) {
      if (e.phase != RecordingPhase.recording) ended.complete(e);
    });

    source.lastSession!.loseSource();
    final event = await ended.future;

    expect(source.lastSession!.stopCalls, 1);
    expect(handle.phase, RecordingPhase.ended);
    expect(manager.active, isNull);
    expect(event.reason, RecordingEndReason.sourceLost);
  });

  test('ingetrokken toestemming stopt met permissionLost', () async {
    final handle = await startMic();
    final ended = Completer<RecordingEvent>();
    handle.events.listen((e) {
      if (e.phase != RecordingPhase.recording) ended.complete(e);
    });

    source.lastSession!.revokePermission();
    final event = await ended.future;

    expect(event.reason, RecordingEndReason.permissionLost);
    expect(handle.phase, RecordingPhase.ended);
    expect(source.lastSession!.stopCalls, 1);
    expect(manager.active, isNull);
  });

  test(
    'volle schijf stopt met storageFailed en laat het resultaat staan',
    () async {
      final handle = await startMic();
      final ended = Completer<RecordingEvent>();
      handle.events.listen((e) {
        if (e.phase != RecordingPhase.recording) ended.complete(e);
      });

      source.lastSession!.failStorage();
      final event = await ended.future;

      expect(event.reason, RecordingEndReason.storageFailed);
      expect(handle.phase, RecordingPhase.ended);
      expect(handle.result, isNotNull);
      expect(manager.active, isNull);
    },
  );

  test('appQuit en moduleDisabled lopen door dezelfde stop', () async {
    for (final reason in [
      RecordingEndReason.appQuit,
      RecordingEndReason.moduleDisabled,
    ]) {
      final handle = await startMic();
      final firstEvent = handle.events.first;
      await manager.stop(reason);
      final event = await firstEvent;
      expect(event.reason, reason, reason: 'reden $reason wordt doorgegeven');
      expect(source.lastSession!.stopCalls, 1);
    }
  });

  test('een tweede stop breekt de track niet twee keer af', () async {
    final handle = await startMic();
    await handle.stop();
    await manager.stop(RecordingEndReason.userStop);
    expect(source.lastSession!.stopCalls, 1);
  });

  test(
    'een faal in stop() markeert de sessie failed, niet verdwenen',
    () async {
      final handle = await startMic();
      source.lastSession!.stopError = const IoFailed('schijf vol');
      final firstEvent = handle.events.first;

      await manager.stop(RecordingEndReason.userStop);
      final event = await firstEvent;

      expect(handle.phase, RecordingPhase.failed);
      expect(handle.error, isA<IoFailed>());
      expect(event.phase, RecordingPhase.failed);
      expect(manager.active, isNull);
    },
  );

  test('een gefaalde start laat geen weesmap in staging achter', () async {
    source.startError = const PermissionDenied('geweigerd');
    await expectLater(startMic, throwsA(isA<PermissionDenied>()));
    // De stagingmap die de manager aanmaakte is van hem — hij ruimt hem op.
    expect(tempDir.listSync(), isEmpty);
    expect(manager.active, isNull);
  });

  test(
    'de stagingmap van een lopende sessie ligt onder de stagingwortel',
    () async {
      final handle = await startMic();
      expect(handle.stagingDir, startsWith(tempDir.path));
      expect(Directory(handle.stagingDir!).existsSync(), isTrue);
      expect(source.lastRequest!.stagingDir, handle.stagingDir);
      await handle.stop();
    },
  );

  test('alleen een afgeronde file met audio vraagt om een keuze', () {
    bool ask({
      bool mounted = true,
      RecordingEndReason? reason = RecordingEndReason.userStop,
      RecordingPhase phase = RecordingPhase.ended,
      bool hasDurableAudio = true,
    }) => wantsFinishedRecordingDialog(
      mounted: mounted,
      reason: reason,
      phase: phase,
      hasDurableAudio: hasDurableAudio,
    );

    expect(ask(), isTrue);
    expect(ask(mounted: false), isFalse);
    expect(ask(reason: null), isFalse);
    expect(ask(reason: RecordingEndReason.appQuit), isFalse);
    expect(ask(reason: RecordingEndReason.moduleDisabled), isFalse);
    expect(ask(reason: RecordingEndReason.sourceLost), isTrue);
    expect(ask(phase: RecordingPhase.recording), isFalse);
    expect(ask(hasDurableAudio: false), isFalse);
  });

  test('de consent die de flow gaf bereikt de bron', () async {
    const geven = RecordingConsent(participantNoticeAcknowledged: true);
    await startMic(withConsent: geven);
    expect(source.lastRequest!.consent.participantNoticeAcknowledged, isTrue);
    await manager.stop(RecordingEndReason.userStop);
  });
}
