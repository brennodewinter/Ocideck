// De module Transcriptie en opname (#2510): standaard uit, keuze bewaard,
// en — anders dan een vergadering — stopt uitzetten een lopende opname
// aantoonbaar. Dat laatste is de helft van de acceptatie die alleen deze
// module kan breken: de sessiegrens kent geen "module uit", de schakelaar
// wel.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging_stub.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/transcription_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transcription/fakes/fake_capture_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        // De tests draaien zonder bestandssysteem: de no-op staging staat
        // toe dat de grens loopt zonder tempmappen te maken.
        recordingStagingProvider.overrideWithValue(
          const NoopRecordingStaging(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('de module staat standaard uit en bewaart de keuze', () async {
    final c = container();
    c.read(transcriptionModuleProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(transcriptionEnabledProvider), isFalse);

    await c.read(transcriptionModuleProvider.notifier).setEnabled(true);
    expect(c.read(transcriptionEnabledProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(transcriptionModuleEnabledKey), isTrue);
    expect(moduleRegistry.map((e) => e.id), contains(ModuleId.transcription));
    // De nieuwste module sluit het register af — de kaartvolgorde-test in
    // online_storage_module_test.dart pint de hele rij.
    expect(moduleRegistry.last.id, ModuleId.transcription);
  });

  test('reveal volgt de schakelaar én blijft aan tijdens een sessie', () async {
    final c = container();
    c.read(transcriptionModuleProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(transcriptionRevealProvider), isFalse);

    await c.read(transcriptionModuleProvider.notifier).setEnabled(true);
    expect(c.read(transcriptionRevealProvider), isTrue);

    await c.read(transcriptionModuleProvider.notifier).setEnabled(false);
    expect(c.read(transcriptionRevealProvider), isFalse);
  });

  test('module uit terwijl de opname loopt stopt de capture', () async {
    final c = container();
    c.read(transcriptionModuleProvider);
    await Future<void>.delayed(Duration.zero);
    await c.read(transcriptionModuleProvider.notifier).setEnabled(true);

    final source = FakeCaptureSource();
    final handle = await c
        .read(recordingSessionProvider.notifier)
        .start(
          source,
          kinds: const {CaptureSourceKind.microphone},
          consent: const RecordingConsent(participantNoticeAcknowledged: true),
        );
    final ended = Completer<RecordingEvent>();
    handle.events.listen((e) {
      if (e.phase != RecordingPhase.recording) ended.complete(e);
    });
    expect(c.read(recordingSessionProvider), isNotNull);

    await c.read(transcriptionModuleProvider.notifier).setEnabled(false);
    final event = await ended.future;

    expect(event.reason, RecordingEndReason.moduleDisabled);
    expect(source.lastSession!.stopCalls, 1);
    expect(c.read(recordingSessionProvider), isNull);
  });

  test('appQuit via de notifier stopt dezelfde capture', () async {
    final c = container();
    final source = FakeCaptureSource();
    await c
        .read(recordingSessionProvider.notifier)
        .start(
          source,
          kinds: const {CaptureSourceKind.microphone},
          consent: const RecordingConsent(participantNoticeAcknowledged: true),
        );

    await c
        .read(recordingSessionProvider.notifier)
        .stopAll(RecordingEndReason.appQuit);

    expect(source.lastSession!.stopCalls, 1);
    expect(c.read(recordingSessionProvider), isNull);
  });

  testWidgets('de modulekaart schakelt de module aan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TranscriptionModuleCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transcriptie en opname'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
