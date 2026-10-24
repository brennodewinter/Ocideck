// De microfoondialoog (#2516) met een script in plaats van een apparaat.
// Laden beschrijft alleen. De niveautest geeft de poort terug. Opnemen
// stuurt de systeemstandaard door als geen apparaat gekozen is.
//
// De staging is een nepstaging: `Directory.list` komt in een widgettest
// niet terug, en deze toets gaat over de dialoog, niet over de schijf.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/mic_capture_port.dart';
import 'package:ocideck/services/transcription/mic_session_gate.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/shell/record_microphone_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Staging implements RecordingStaging {
  @override
  Future<String?> createSessionDir() async => '/tmp/ocideck-mic-test';

  @override
  Future<void> discardDir(String? dir) async {}

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

class _Live implements MicCaptureLive {
  final framesCtrl = StreamController<MicPcmFrame>.broadcast();
  final endedCtrl = StreamController<CaptureEndCause>.broadcast();
  var stops = 0;

  @override
  MicStreamFormat get format =>
      const MicStreamFormat(sampleRate: 16000, channels: 1);

  @override
  Stream<MicPcmFrame> get frames => framesCtrl.stream;

  @override
  Stream<CaptureEndCause> get ended => endedCtrl.stream;

  @override
  Future<void> stop() async {
    stops++;
    if (!framesCtrl.isClosed) await framesCtrl.close();
    if (!endedCtrl.isClosed) await endedCtrl.close();
  }
}

class _Port extends MicCapturePort {
  var describeCalls = 0;
  var openCalls = 0;
  final opened = <String?>[];
  final live = _Live();

  @override
  Future<MicPlatformFacts> describe() async {
    describeCalls++;
    return const MicPlatformFacts(
      availability: CaptureAvailability.available,
      inputs: [
        MicInput(id: 'usb-1', label: 'USB-mic', transport: MicTransport.usb),
      ],
    );
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    openCalls++;
    opened.add(deviceId);
    return live;
  }
}

class _Session implements CaptureSession {
  @override
  String get durablePath => '/tmp/ocideck-mic-test/recording.wav';

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => const Stream.empty();

  @override
  Future<RecordedAudio> stop() async => RecordedAudio(
    durablePath: durablePath,
    duration: Duration.zero,
    kinds: const {CaptureSourceKind.microphone},
  );
}

class _Source extends CaptureSource {
  _Source(this.port);

  final _Port port;
  CaptureRequest? last;

  @override
  CaptureSourceKind get kind => CaptureSourceKind.microphone;

  @override
  Future<CaptureAvailability> probe() async => CaptureAvailability.available;

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    last = request;
    await port.open(deviceId: request.inputDeviceId);
    return _Session();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Port port;
  late _Source source;
  late MicSessionGate gate;
  late ProviderContainer container;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    port = _Port();
    source = _Source(port);
    gate = MicSessionGate();
    container = ProviderContainer(
      overrides: [
        micCapturePortProvider.overrideWithValue(port),
        micSessionGateProvider.overrideWithValue(gate),
        recordingStagingProvider.overrideWithValue(_Staging()),
        captureSourcesProvider.overrideWithValue({
          CaptureSourceKind.microphone: source,
        }),
      ],
    );
  });

  tearDown(() async {
    final handle = container.read(recordingSessionProvider);
    if (handle != null) await handle.stop();
    container.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => recordMicrophone(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('laden beschrijft de invoer en opent haar niet', (tester) async {
    expect(microphoneRecordingOffered, isTrue);
    await open(tester);
    expect(
      recordMicrophoneLabel(
        AppLocalizations.of(tester.element(find.text('open'))),
      ),
      'Microfoon opnemen…',
    );
    expect(find.text('Microfoon opnemen'), findsOneWidget);
    expect(find.text('Systeemstandaard'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('USB-mic (USB)'), findsWidgets);
    expect(port.describeCalls, 1);
    expect(port.openCalls, 0);
  });

  testWidgets('de niveautest geeft de poort terug en bewaart niets', (
    tester,
  ) async {
    await open(tester);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Niveau testen'),
    );
    expect(button.onPressed, isNotNull, reason: 'gate=${gate.holder}');
    await tester.ensureVisible(
      find.widgetWithText(TextButton, 'Niveau testen'),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Niveau testen'));
    // Eén pump hervat `await open`, de volgende plant de timer van 1,5 s.
    await tester.pump();
    await tester.pump();
    expect(port.openCalls, 1);
    expect(gate.holder, MicHolder.recording);
    // Sluiten terwijl de test loopt geeft de microfoon terug. De route
    // blijft staan tot de sluitanimatie voorbij is; die is korter dan
    // de niveautest, dus de timer stopt de opname niet zelf.
    await tester.tap(find.text('Annuleren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Microfoon opnemen'), findsNothing);
    expect(port.live.stops, 1);
    expect(gate.holder, isNull);
  });

  testWidgets('Opnemen start op de systeemstandaard', (tester) async {
    await open(tester);
    await tester.tap(find.text('Opnemen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Microfoon opnemen'), findsNothing);
    expect(source.last?.inputDeviceId, isNull);
    expect(port.opened, [null]);
    expect(container.read(recordingSessionProvider), isNotNull);
  });
}
