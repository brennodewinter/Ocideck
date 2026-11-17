// Na Stop kiest de gebruiker: nu transcriberen, zeven dagen bewaren,
// of weggooien (#2516). Bronverlies en een volle schijf zeggen dat,
// in plaats van de gewone bewaartekst.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/recording_session.dart';
import 'package:ocideck/services/transcription/recording_staging.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/recording_finished_dialog.dart';
import 'package:ocideck/widgets/dialogs/transcribe_file_dialog.dart';

class _Staging implements RecordingStaging {
  final discarded = <String?>[];

  @override
  Future<String?> createSessionDir() async => null;

  @override
  Future<void> discardDir(String? dir) async => discarded.add(dir);

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}

  @override
  Future<List<String>> listSessionDirs() async => const [];
}

class _File extends FileCaptureSource {
  @override
  CaptureSourceKind get kind => CaptureSourceKind.file;

  @override
  Future<CaptureAvailability> probe() async => CaptureAvailability.available;

  @override
  Future<FileSourceInfo> describe(String sourcePath) async => FileSourceInfo(
    path: sourcePath,
    sizeBytes: 64,
    container: MediaContainer.wav,
    duration: const Duration(seconds: 1),
    engineReadsDirectly: true,
    decodable: true,
  );

  @override
  Future<FileCaptureSession> start(CaptureRequest request) =>
      throw UnsupportedError('deze toets start geen transcriptie');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Staging staging;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    staging = _Staging();
    WebAssetStore.clear();
  });

  tearDown(() {
    WebAssetStore.clear();
    debugDeliversByDownload = null;
    debugDownloadSink = null;
  });

  Future<void> open(
    WidgetTester tester,
    RecordingEndReason reason, {
    RecordedAudio? recording,
  }) async {
    final container = ProviderContainer(
      overrides: [
        recordingStagingProvider.overrideWithValue(staging),
        captureSourcesProvider.overrideWithValue({
          CaptureSourceKind.file: _File(),
        }),
      ],
    );
    addTearDown(container.dispose);
    final audio =
        recording ??
        const RecordedAudio(
          durablePath: '/tmp/ocideck-mic/recording.wav',
          duration: Duration(seconds: 3),
          kinds: {CaptureSourceKind.microphone},
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
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showRecordingFinishedDialog(
                  context,
                  ref,
                  audio: audio,
                  sessionDir: '/tmp/ocideck-mic',
                  reason: reason,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  RecordedAudio webAudio() {
    final path = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3]),
      name: 'opname.webm',
    );
    final lease = WebAssetStore.lease([path]);
    return RecordedAudio(
      durablePath: path,
      duration: const Duration(seconds: 1),
      kinds: const {CaptureSourceKind.microphone},
      onRelease: lease.release,
    );
  }

  testWidgets(
    'web biedt audio aan als download en ruimt na weggooien gericht op',
    (tester) async {
      debugDeliversByDownload = true;
      addTearDown(WebAssetStore.registerRoots(() => {}));
      final audio = webAudio();
      Uint8List? delivered;
      debugDownloadSink = (name, bytes, mime) {
        expect(name, 'opname.webm');
        delivered = bytes;
        return true;
      };
      await open(tester, RecordingEndReason.userStop, recording: audio);
      expect(find.text('Bewaar voor later'), findsNothing);
      expect(find.textContaining('zeven dagen'), findsNothing);
      expect(find.textContaining('gaat de audio verloren'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(delivered, [1, 2, 3]);
      expect(find.textContaining('Aangeboden als download:'), findsOneWidget);
      WebAssetStore.retain({});
      expect(WebAssetStore.bytesFor(audio.durablePath), [1, 2, 3]);
      await tester.tap(find.text('Opname weggooien'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(WebAssetStore.bytesFor(audio.durablePath), isNull);
      expect(staging.discarded, isEmpty);
    },
  );

  testWidgets(
    'geweigerde download houdt de opname beschikbaar; sluiten geeft haar vrij',
    (tester) async {
      debugDeliversByDownload = true;
      addTearDown(WebAssetStore.registerRoots(() => {}));
      final audio = webAudio();
      debugDownloadSink = (_, _, _) => false;
      await open(tester, RecordingEndReason.userStop, recording: audio);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(
        find.text('Het bestand kon niet worden opgeslagen.'),
        findsOneWidget,
      );
      expect(WebAssetStore.bytesFor(audio.durablePath), [1, 2, 3]);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(WebAssetStore.bytesFor(audio.durablePath), isNull);
    },
  );

  testWidgets('handoff naar transcriptie overleeft de gesloten bewaarkeuze', (
    tester,
  ) async {
    debugDeliversByDownload = true;
    addTearDown(WebAssetStore.registerRoots(() => {}));
    final audio = webAudio();
    await open(tester, RecordingEndReason.userStop, recording: audio);
    await tester.tap(find.text('Nu transcriberen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TranscribeFileDialog), findsOneWidget);
    WebAssetStore.retain({});
    expect(WebAssetStore.bytesFor(audio.durablePath), [1, 2, 3]);
    await tester.tap(find.text('Annuleren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(WebAssetStore.bytesFor(audio.durablePath), isNull);
  });

  testWidgets('een gewone stop biedt transcriberen, bewaren en weggooien', (
    tester,
  ) async {
    await open(tester, RecordingEndReason.userStop);
    expect(find.text('Opname bewaard'), findsOneWidget);
    expect(find.textContaining('zeven dagen'), findsOneWidget);

    await tester.tap(find.text('Bewaar voor later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Opname bewaard'), findsNothing);
    expect(staging.discarded, isEmpty);
  });

  testWidgets('weggooien wist de sessiemap', (tester) async {
    await open(tester, RecordingEndReason.userStop);
    await tester.tap(find.text('Opname weggooien'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(staging.discarded, ['/tmp/ocideck-mic']);
  });

  testWidgets('nu transcriberen opent de bestandsdialoog', (tester) async {
    await open(tester, RecordingEndReason.userStop);
    await tester.tap(find.text('Nu transcriberen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TranscribeFileDialog), findsOneWidget);
    expect(find.text('Microfoonopname'), findsOneWidget);
  });

  testWidgets('bronverlies en een volle schijf zeggen wat er gebeurde', (
    tester,
  ) async {
    await open(tester, RecordingEndReason.sourceLost);
    expect(find.textContaining('viel weg'), findsOneWidget);
    await tester.tap(find.text('Bewaar voor later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await open(tester, RecordingEndReason.storageFailed);
    expect(find.textContaining('schijf raakte vol'), findsOneWidget);
  });
}
