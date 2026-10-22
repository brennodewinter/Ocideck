// De opname-indicator (#2510): aanwezig precies zolang de sessie loopt,
// met bron, duur en Stop — bereikbaar voor toetsenbord en schermlezer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging_stub.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/panels/recording_indicator.dart';

import 'transcription/fakes/fake_capture_source.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  late ProviderContainer container;
  late FakeCaptureSource source;

  setUp(() {
    source = FakeCaptureSource();
    container = ProviderContainer(
      overrides: [
        recordingStagingProvider.overrideWithValue(
          const NoopRecordingStaging(),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: RecordingIndicator())),
    ),
  );

  Future<RecordingHandle> startMic() => container
      .read(recordingSessionProvider.notifier)
      .start(
        source,
        kinds: const {CaptureSourceKind.microphone},
        consent: const RecordingConsent(participantNoticeAcknowledged: true),
      );

  testWidgets('zonder sessie is er geen strook', (tester) async {
    await pump(tester);
    expect(find.textContaining('Opname loopt'), findsNothing);
  });

  testWidgets('met sessie staan bron, duur en Stop er', (tester) async {
    await startMic();
    await pump(tester);
    await tester.pump();

    expect(find.textContaining('Opname loopt: Microfoon'), findsOneWidget);
    expect(find.byIcon(Icons.stop_outlined), findsOneWidget);
  });

  testWidgets('de strook is een live region met de stop-benadering erbij', (
    tester,
  ) async {
    await startMic();
    await pump(tester);
    await tester.pump();

    final live = tester
        .widgetList<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        )
        .toList();
    expect(live, isNotEmpty);
    expect(
      live.any((s) => (s.properties.label ?? '').contains('Opname loopt')),
      isTrue,
    );
    // De Stop-knop draagt een eigen benadering: "Stop" alleen zegt een
    // schermlezer niet wát er stopt.
    final stop = tester
        .widgetList<Semantics>(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                w.properties.label == 'Opname stoppen',
          ),
        )
        .toList();
    expect(stop, hasLength(1));
  });

  testWidgets('Stop breekt de capture af en doet de strook verdwijnen', (
    tester,
  ) async {
    final handle = await startMic();
    await pump(tester);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.stop_outlined));
    await tester.pumpAndSettle();

    expect(source.lastSession!.stopCalls, 1);
    expect(handle.phase, RecordingPhase.ended);
    expect(find.textContaining('Opname loopt'), findsNothing);
  });

  testWidgets('bronverlies maakt de strook weg zodra de sessie eindigt', (
    tester,
  ) async {
    await startMic();
    await pump(tester);
    await tester.pump();

    source.lastSession!.loseSource();
    await tester.pumpAndSettle();

    expect(find.textContaining('Opname loopt'), findsNothing);
    expect(source.lastSession!.stopCalls, 1);
  });
}
