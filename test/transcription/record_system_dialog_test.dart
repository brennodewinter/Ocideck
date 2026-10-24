// De systeemdialoog toont de deelnemersmelding en peilt vóór de start.
// Opnemen is de bevestiging; laden opent de bron niet.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/shell/record_system_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Staging implements RecordingStaging {
  @override
  Future<String?> createSessionDir() async => '/tmp/ocideck-system-test';

  @override
  Future<void> discardDir(String? dir) async {}

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

class _Session implements CaptureSession {
  @override
  String get durablePath => '/tmp/ocideck-system-test/recording.wav';

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => null;

  @override
  Future<RecordedAudio> stop() async => const RecordedAudio(
    durablePath: '/tmp/ocideck-system-test/recording.wav',
    duration: Duration.zero,
    kinds: {CaptureSourceKind.systemAudio},
  );
}

class _Source extends CaptureSource {
  var probes = 0;
  CaptureRequest? last;

  @override
  CaptureSourceKind get kind => CaptureSourceKind.systemAudio;

  @override
  Future<CaptureAvailability> probe() async {
    probes++;
    return CaptureAvailability.tryAfterPermission;
  }

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    last = request;
    return _Session();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Source source;
  late ProviderContainer container;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    source = _Source();
    container = ProviderContainer(
      overrides: [
        recordingStagingProvider.overrideWithValue(_Staging()),
        captureSourcesProvider.overrideWithValue({
          CaptureSourceKind.systemAudio: source,
        }),
      ],
    );
  });

  tearDown(() async {
    final handle = container.read(recordingSessionProvider);
    if (handle != null) await handle.stop();
    container.dispose();
  });

  testWidgets('laden peilt en Opnemen bevestigt de melding', (tester) async {
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
                onPressed: () => recordSystem(context),
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
    expect(source.probes, 1);
    expect(source.last, isNull);
    expect(
      find.text('Opnemen van anderen kan hun toestemming vragen.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Opnemen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(source.last!.consent.participantNoticeAcknowledged, isTrue);
    expect(source.last!.kinds, {CaptureSourceKind.systemAudio});
  });

  testWidgets('labels en aanbod volgen de geregistreerde bronnen', (
    tester,
  ) async {
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
            body: Consumer(
              builder: (context, ref, _) => Text(
                '${systemRecordingOffered(ref)} '
                '${combinationRecordingOffered(ref)} '
                '${recordSystemLabel(context.l10n)} '
                '${recordCombinationLabel(context.l10n)}',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('true false'), findsOneWidget);
    expect(find.textContaining('Systeemgeluid opnemen…'), findsOneWidget);
    expect(
      find.textContaining('Microfoon en systeemgeluid opnemen…'),
      findsOneWidget,
    );

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
                onPressed: () => recordCombination(context),
                child: const Text('combi'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('combi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
