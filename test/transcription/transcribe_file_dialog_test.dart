// Widgettests voor de bestandstranscriptie-dialoog (#2515): de
// voorbeschouwing toont eerlijk wat er staat, Start loopt door naar een
// nieuw transcriptdocument, en Stop breekt af zonder een half resultaat.
//
// De bestandsbron en de engine zijn fakes — er verlaat niets het apparaat,
// er draait geen whisper-cli. Wat getoetst wordt is de flow zelf: wat de
// gebruiker ziet vóór, tijdens en na.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/widgets/dialogs/transcribe_file_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

Uint8List _wav({int seconds = 2}) {
  const rate = 16000;
  final dataLen = seconds * rate * 2;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(36 + dataLen),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ..._le32(16),
    ..._le16(1),
    ..._le16(1),
    ..._le32(rate),
    ..._le32(rate * 2),
    ..._le16(2),
    ..._le16(16),
    ...'data'.codeUnits,
    ..._le32(dataLen),
    ...List.filled(dataLen, 0),
  ]);
}

/// Een bestandsbron die één vast WAV-bestand beschrijft en een sessie
/// teruggeeft die onmiddellijk voltooid — geen decode, geen subprocess.
class _FakeFileSource extends FileCaptureSource {
  _FakeFileSource(this.path, {this.startError});

  final String path;
  final Object? startError;

  @override
  CaptureSourceKind get kind => CaptureSourceKind.file;

  @override
  Future<CaptureAvailability> probe() async => CaptureAvailability.available;

  @override
  Future<FileSourceInfo> describe(String sourcePath) async {
    if (sourcePath != path) throw IoFailed('onverwacht pad: $sourcePath');
    return FileSourceInfo(
      path: path,
      sizeBytes: 64,
      container: MediaContainer.wav,
      duration: const Duration(seconds: 2),
      engineReadsDirectly: true,
      decodable: true,
    );
  }

  @override
  Future<FileCaptureSession> start(CaptureRequest request) async {
    if (startError != null) throw startError!;
    return _FakeSession(path);
  }
}

class _FakeSession extends FileCaptureSession {
  _FakeSession(this.path);
  final String path;

  @override
  late final String durablePath = path;

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => null;

  @override
  void cancel() {}

  @override
  Future<RecordedAudio> stop() async => RecordedAudio(
    durablePath: path,
    duration: const Duration(seconds: 2),
    kinds: const {CaptureSourceKind.file},
  );
}

/// Een engine die één vast resultaat teruggeeft en voortgang streamt.
class _FakeEngine implements TranscriptionEngine {
  _FakeEngine(
    this._segments, {
    this.throwOnTranscribe,
    this.caps = const EngineCapabilities(timestamps: true),
  });

  final EngineCapabilities caps;
  TranscriptionOptions? receivedOptions;

  final List<TranscriptSegment> _segments;
  final Object? throwOnTranscribe;

  @override
  EngineKind get kind => EngineKind.local;

  @override
  Future<EngineCapabilities> capabilities() async => caps;

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    receivedOptions = options;
    if (throwOnTranscribe != null) throw throwOnTranscribe!;
    // Speel de voortgang na: twee stappen, dan klaar.
    if (options.onProgress != null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      options.onProgress!(0.5);
      options.onProgress!(1.0);
    }
    return TranscriptResult(segments: _segments);
  }

  @override
  Stream<PartialTranscript>? transcribeLive(
    Stream<AudioChunk> audio, {
    TranscriptionOptions? options,
  }) => null;

  @override
  void cancel() {}
}

class _PendingCapabilitiesEngine extends _FakeEngine {
  _PendingCapabilitiesEngine() : super(const []);
  final pending = Completer<EngineCapabilities>();
  @override
  Future<EngineCapabilities> capabilities() => pending.future;
}

class _DelayedEngine extends _FakeEngine {
  _DelayedEngine() : super(const []);
  final result = Completer<TranscriptResult>();
  bool started = false;
  bool cancelled = false;

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) {
    started = true;
    return result.future;
  }

  @override
  void cancel() => cancelled = true;
}

/// De staging-hulp die niks aanraakt — de dialoog hoeft geen echte map.
class _NoopStaging implements RecordingStaging {
  @override
  Future<String?> createSessionDir() async => null;

  @override
  Future<void> discardDir(String? dir) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

Widget app(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  late Directory tmp;
  late String wavPath;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    WebAssetStore.clear();
    tmp = await Directory.systemTemp.createTemp('dialog_test_');
    wavPath = '${tmp.path}/clip.wav';
    await File(wavPath).writeAsBytes(_wav(seconds: 2));
  });

  tearDown(() async {
    WebAssetStore.clear();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets(
    'sluiten tijdens ASR annuleert en bewaart audio tot de taak afrondt',
    (tester) async {
      final path = WebAssetStore.put(_wav(), name: 'bron.wav');
      final engine = _DelayedEngine();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showTranscribeFileDialog(
                context,
                sourcePath: path,
                displayName: 'bron.wav',
              ),
              child: const Text('open'),
            ),
          ),
          overrides: [
            captureSourcesProvider.overrideWithValue({
              CaptureSourceKind.file: _FakeFileSource(path),
            }),
            transcriptionEngineProvider.overrideWithValue(engine),
            recordingStagingProvider.overrideWithValue(_NoopStaging()),
            recoveryServiceProvider.overrideWithValue(
              RecoveryService(baseDir: tmp),
            ),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      final tabs = container.read(tabsProvider.notifier);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      tabs.sweepWebAssets();
      expect(
        WebAssetStore.bytesFor(path),
        isNotNull,
        reason: 'voorbeschouwing bezit de bron',
      );
      await tester.tap(find.text('Transcriberen'));
      await tester.pump();
      expect(engine.started, isTrue);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(engine.cancelled, isTrue);
      expect(
        WebAssetStore.bytesFor(path),
        isNotNull,
        reason: 'de nog afrondende taak bezit de bron',
      );
      engine.result.complete(
        const TranscriptResult(segments: [TranscriptSegment(text: 'te laat')]),
      );
      await tester.pumpAndSettle();
      expect(WebAssetStore.bytesFor(path), isNull);
      expect(
        container.read(tabsProvider).tabs.single.content,
        isA<DeckTabContent>(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voorbeschouwing toont naam, formaat en duur vóór Start', (
    tester,
  ) async {
    final source = _FakeFileSource(wavPath);
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: source,
          }),
          transcriptionEngineProvider.overrideWithValue(
            _FakeEngine(const [
              TranscriptSegment(text: 'Hallo wereld', start: Duration.zero),
            ]),
          ),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('clip.wav'), findsOneWidget);
    expect(find.text('WAV'), findsOneWidget);
    expect(find.text('0:02'), findsOneWidget);
    expect(find.text('Transcriberen'), findsOneWidget);
  });

  testWidgets('diarisatie is expliciet en talen volgen de servercapability', (
    tester,
  ) async {
    final engine = _FakeEngine(
      const [
        TranscriptSegment(
          text: 'Hallo',
          start: Duration.zero,
          end: Duration(seconds: 1),
          speakerIds: ['a'],
        ),
      ],
      caps: const EngineCapabilities(
        languages: {'nl', 'en'},
        automaticLanguage: false,
        timestamps: true,
        diarization: true,
      ),
    );
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: _FakeFileSource(wavPath),
          }),
          transcriptionEngineProvider.overrideWithValue(engine),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final language = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(language.items!.map((item) => item.value), ['en', 'nl']);
    expect(language.value, 'en');
    final checkbox = find.widgetWithText(
      CheckboxListTile,
      'Sprekers onderscheiden',
    );
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcriberen'));
    await tester.pumpAndSettle();
    expect(engine.receivedOptions!.diarize, isTrue);
    expect(engine.receivedOptions!.language, 'en');
  });

  testWidgets('late capabilities van een verlaten route blijven genegeerd', (
    tester,
  ) async {
    final previous = _PendingCapabilitiesEngine();
    final next = _FakeEngine(const []);
    final source = _FakeFileSource(wavPath);
    final staging = _NoopStaging();
    List<Override> overrides(TranscriptionEngine engine) => [
      captureSourcesProvider.overrideWithValue({
        CaptureSourceKind.file: source,
      }),
      transcriptionEngineProvider.overrideWithValue(engine),
      recordingStagingProvider.overrideWithValue(staging),
    ];
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: overrides(previous),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.updateOverrides(overrides(next));
    await tester.pumpAndSettle();
    previous.pending.complete(
      const EngineCapabilities(languages: {'pl'}, diarization: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sprekers onderscheiden'), findsNothing);
    final language = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(language.items!.map((item) => item.value), ['auto']);
  });

  testWidgets(
    'meerdere talen blijft een expliciete capabilitygestuurde keuze',
    (tester) async {
      final engine = _FakeEngine(
        const [TranscriptSegment(text: 'Hallo. Hello.')],
        caps: const EngineCapabilities(
          languages: {'nl', 'en', 'pl'},
          languageSwitching: true,
        ),
      );
      await tester.pumpWidget(
        app(
          TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
          overrides: [
            captureSourcesProvider.overrideWithValue({
              CaptureSourceKind.file: _FakeFileSource(wavPath),
            }),
            transcriptionEngineProvider.overrideWithValue(engine),
            recordingStagingProvider.overrideWithValue(_NoopStaging()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButton<String>);
      expect(tester.widget<DropdownButton<String>>(dropdown).value, 'auto');
      expect(
        tester
            .widget<DropdownButton<String>>(dropdown)
            .items!
            .map((x) => x.value),
        ['auto', 'mixed', 'en', 'nl', 'pl'],
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meerdere talen in deze opname').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transcriberen'));
      await tester.pumpAndSettle();
      expect(engine.receivedOptions!.languageSwitching, isTrue);
      expect(engine.receivedOptions!.language, isNull);
    },
  );

  testWidgets('Start loopt door en opent een nieuw transcriptdocument', (
    tester,
  ) async {
    final source = _FakeFileSource(wavPath);
    final segments = [
      TranscriptSegment(text: 'Hallo wereld', start: Duration.zero),
      TranscriptSegment(text: 'en allemaal', start: const Duration(seconds: 1)),
    ];
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: source,
          }),
          transcriptionEngineProvider.overrideWithValue(_FakeEngine(segments)),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transcriberen'));
    await tester.pumpAndSettle();

    // De dialoog is weg — het resultaat opende als nieuw document.
    expect(find.byType(TranscribeFileDialog), findsNothing);
  });

  testWidgets('een onleesbare bron toont de fout in het venster', (
    tester,
  ) async {
    final source = _FakeFileSource(
      wavPath,
      startError: const DecodeFailed('kapotte header'),
    );
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: source,
          }),
          transcriptionEngineProvider.overrideWithValue(_FakeEngine(const [])),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transcriberen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('kapotte header'), findsOneWidget);
    expect(find.text('Sluiten'), findsOneWidget);
  });

  testWidgets('een enginefout blijft in het venster, geen crash', (
    tester,
  ) async {
    final source = _FakeFileSource(wavPath);
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: source,
          }),
          transcriptionEngineProvider.overrideWithValue(
            _FakeEngine(
              const [],
              throwOnTranscribe: const EngineUnavailable('model ontbreekt'),
            ),
          ),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transcriberen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('model ontbreekt'), findsOneWidget);
  });

  testWidgets(
    'een callopname krijgt vergaderingsprovenance en een ontbrekend-regel '
    '(#2530)',
    (tester) async {
      // De callsessie van #2529 schreef `sources.json` naast de mix-wav;
      // de pass herkent dat — bronsoort én gaten komen in het document.
      // Synchroon geschreven: de testbody zit in de fake-zone waar een
      // dart:io-future nooit terugkomt.
      File(p.join(tmp.path, 'sources.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'sources': [
            {'silenceTicks': 50},
            {'silenceTicks': 0},
          ],
        }),
      );
      final overrides = [
        captureSourcesProvider.overrideWithValue({
          CaptureSourceKind.file: _FakeFileSource(wavPath),
        }),
        transcriptionEngineProvider.overrideWithValue(
          _FakeEngine(const [
            TranscriptSegment(text: 'Hallo wereld', start: Duration.zero),
          ]),
        ),
        recordingStagingProvider.overrideWithValue(_NoopStaging()),
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: tmp),
        ),
      ];
      await tester.pumpWidget(
        app(
          TranscribeFileDialog(
            sourcePath: wavPath,
            displayName: 'Vergaderingsopname',
          ),
          overrides: overrides,
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TranscribeFileDialog)),
      );
      await tester.tap(find.text('Transcriberen'));
      await tester.pumpAndSettle();

      final doc = container
          .read(tabsProvider)
          .current!
          .documentNotifier!
          .state
          .document!;
      expect(doc.source, contains('Bron: vergadering'));
      expect(
        doc.source,
        contains(
          'Ontbrekend: ~1 s bronaudio over 1 bron(nen) — track- of '
          'netwerkverlies tijdens de opname.',
        ),
      );
    },
  );

  testWidgets('een los bestand zonder manifest claimt geen vergadering', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        TranscribeFileDialog(sourcePath: wavPath, displayName: 'clip.wav'),
        overrides: [
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: _FakeFileSource(wavPath),
          }),
          transcriptionEngineProvider.overrideWithValue(
            _FakeEngine(const [
              TranscriptSegment(text: 'Hallo wereld', start: Duration.zero),
            ]),
          ),
          recordingStagingProvider.overrideWithValue(_NoopStaging()),
          recoveryServiceProvider.overrideWithValue(
            RecoveryService(baseDir: tmp),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TranscribeFileDialog)),
    );
    await tester.tap(find.text('Transcriberen'));
    await tester.pumpAndSettle();

    final doc = container
        .read(tabsProvider)
        .current!
        .documentNotifier!
        .state
        .document!;
    expect(doc.source, contains('Bron: bestand'));
    expect(doc.source, isNot(contains('Ontbrekend')));
  });
}
