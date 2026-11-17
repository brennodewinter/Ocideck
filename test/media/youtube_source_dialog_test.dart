import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/media/youtube_reference.dart';
import 'package:ocideck/services/media/youtube_source_client.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source_io.dart';
import 'package:ocideck/services/transcription/file_capture_source.dart'
    show FileSourceInfo;
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/recording_staging_io.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/transcribe_file_dialog.dart';
import 'package:ocideck/widgets/media/youtube_source_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/pump_until.dart';

class _Transport implements AsrTransport {
  final actions = <String>[];
  Completer<AsrResponse>? pending;
  bool cancelled = false;
  bool serverCuts = false;
  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    required Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    final action = url.pathSegments.last;
    actions.add(action);
    final response = switch (action) {
      'capabilities' => {
        'captions': true,
        'audio': true,
        'audio_fragments': serverCuts,
        'audio_encoding': 'pcm16-wav',
      },
      'metadata' => {
        'title': 'Public fixture',
        'duration_ms': 3000,
        'status': 'completed',
        'audio': true,
        'tracks': [
          {'id': 'manual:en', 'language': 'en', 'kind': 'manual'},
          {'id': 'automatic:en', 'language': 'en', 'kind': 'automatic'},
        ],
      },
      'captions' => {
        'track': jsonDecode(utf8.decode(body!))['track'],
        'format': 'vtt',
        'text': 'WEBVTT\n\n00:00:01.200 --> 00:00:01.500\nCaption text\n',
      },
      'audio' => _audio(body!),
      _ => <String, Object?>{},
    };
    return AsrSendHandle(
      done:
          pending?.future ??
          Future.value(
            AsrResponse(
              200,
              jsonEncode({
                'protocol': 'ocideck-youtube',
                'version': 1,
                'video_id': 'M7lc1UVf-VE',
                ...response,
              }),
            ),
          ),
      cancel: () {
        cancelled = true;
        final value = pending;
        if (value != null && !value.isCompleted) {
          value.completeError(const AsrRequestException('cancelled'));
        }
      },
    );
  }

  Map<String, Object?> _audio(Uint8List body) {
    final fields = jsonDecode(utf8.decode(body)) as Map;
    final start = serverCuts ? fields['start_ms'] as int : 0;
    final end = serverCuts && fields['end_ms'] != 0
        ? fields['end_ms'] as int
        : 3000;
    return {
      'extension': 'wav',
      'source_offset_ms': start,
      'base64': base64Encode(encodePcmWav(Float32List((end - start) * 16))),
    };
  }
}

class _InspectFileSource extends IoFileCaptureSource {
  String? openedPath;
  @override
  Future<FileSourceInfo> describe(String sourcePath) {
    openedPath = sourcePath;
    return super.describe(sourcePath);
  }
}

class _InspectEngine implements TranscriptionEngine {
  Duration? receivedDuration;
  @override
  EngineKind get kind => EngineKind.local;
  @override
  Future<EngineCapabilities> capabilities() async =>
      const EngineCapabilities(timestamps: true, languages: {'en'});
  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    final bytes = await File(audio.path).readAsBytes();
    receivedDuration = parseWavHeader(bytes, bytes.length)!.duration;
    return const TranscriptResult(
      segments: [
        TranscriptSegment(
          text: 'ASR text',
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 500),
        ),
      ],
    );
  }

  @override
  void cancel() {}
  @override
  Stream<PartialTranscript>? transcribeLive(
    Stream<AudioChunk> audio, {
    TranscriptionOptions? options,
  }) => null;
}

void main() {
  late Directory temp;
  late _Transport transport;
  late _InspectEngine engine;
  late _InspectFileSource fileSource;
  late ProviderContainer container;
  var clients = 0;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'allowRemoteMedia': true});
    temp = await Directory.systemTemp.createTemp('youtube-ui-test-');
    transport = _Transport();
    engine = _InspectEngine();
    fileSource = _InspectFileSource();
    clients = 0;
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {bool enabled = true}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transcriptionEnabledProvider.overrideWithValue(enabled),
          transcriptionEngineProvider.overrideWithValue(engine),
          captureSourcesProvider.overrideWithValue({
            CaptureSourceKind.file: fileSource,
          }),
          recordingStagingProvider.overrideWithValue(
            IoRecordingStaging(baseDir: Directory('${temp.path}/staging')),
          ),
          recoveryServiceProvider.overrideWithValue(
            RecoveryService(baseDir: temp),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                container = ProviderScope.containerOf(context);
                return TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => YoutubeSourceDialog(
                      reference: YoutubeReference.parse(
                        'https://youtu.be/M7lc1UVf-VE?t=1&end=2',
                      )!,
                      clientFactory: (profile, allowed, key) {
                        clients++;
                        return YoutubeSourceClient(
                          destination: profile,
                          mayUseNetwork: allowed,
                          transport: transport,
                          apiKey: key,
                        );
                      },
                    ),
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> load(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('youtube-source-endpoint')),
      'http://127.0.0.1:8866',
    );
    await tester.tap(find.text('Video-informatie ophalen'));
    await tester.pumpAndSettle();
  }

  testWidgets('proposal and rejection do not construct a client or fetch', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Deze video transcriberen?'), findsOneWidget);
    expect(clients, 0);
    expect(transport.actions, isEmpty);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(clients, 0);
    expect(
      container
          .read(tabsProvider)
          .tabs
          .every((tab) => tab.documentNotifier == null),
      isTrue,
    );
  });

  testWidgets('disabled module exposes settings and starts no extraction', (
    tester,
  ) async {
    await open(tester, enabled: false);
    expect(find.text('Instellingen openen'), findsOneWidget);
    expect(find.text('Video-informatie ophalen'), findsNothing);
    expect(transport.actions, isEmpty);
  });

  testWidgets(
    'manual captions produce editable provenance without invoking ASR',
    (tester) async {
      await open(tester);
      await load(tester);
      expect(transport.actions, ['capabilities', 'metadata']);
      await tester.tap(find.text('Ondertitels overnemen'));
      await tester.pumpAndSettle();
      final source = container
          .read(tabsProvider)
          .current!
          .documentNotifier!
          .state
          .document!
          .source;
      expect(source, contains('Handmatige ondertitels'));
      expect(
        source,
        contains('[0:00:01](https://www.youtube.com/watch?v=M7lc1UVf-VE&t=1)'),
      );
      expect(source, contains('Caption text'));
      expect(engine.receivedDuration, isNull);
    },
  );

  testWidgets('closing a real pending handle cancels extraction', (
    tester,
  ) async {
    await open(tester);
    transport.pending = Completer<AsrResponse>();
    await tester.enterText(
      find.byKey(const ValueKey('youtube-source-endpoint')),
      'http://127.0.0.1:8866',
    );
    await tester.tap(find.text('Video-informatie ophalen'));
    await tester.pump();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(transport.cancelled, isTrue);
    expect(
      container
          .read(tabsProvider)
          .tabs
          .every((tab) => tab.documentNotifier == null),
      isTrue,
    );
  });

  testWidgets(
    'audio excerpt is cut before the engine and retains the video clock',
    (tester) async {
      await open(tester);
      await load(tester);
      await tester.tap(find.text('Alleen dit fragment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio downloaden en transcriberen…'));
      await pumpUntil(tester, () {
        final button = find.widgetWithText(FilledButton, 'Transcriberen');
        return button.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(button).onPressed != null;
      });
      expect(find.byType(TranscribeFileDialog), findsOneWidget);
      await tester.tap(find.text('Transcriberen'));
      await pumpUntil(
        tester,
        () =>
            engine.receivedDuration != null &&
            container.read(tabsProvider).current?.documentNotifier != null,
      );
      expect(engine.receivedDuration, const Duration(seconds: 1));
      final source = container
          .read(tabsProvider)
          .current!
          .documentNotifier!
          .state
          .document!
          .source;
      expect(source, contains('"start_us":1200000'));
      expect(source, contains('"end_us":1500000'));
      expect(source, contains('ASR text'));
      await pumpUntil(tester, () => !File(fileSource.openedPath!).existsSync());
    },
  );

  testWidgets('server-cut PCM is not cut twice and keeps the original offset', (
    tester,
  ) async {
    transport.serverCuts = true;
    await open(tester);
    await load(tester);
    await tester.tap(find.text('Alleen dit fragment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio downloaden en transcriberen…'));
    await pumpUntil(tester, () {
      final button = find.widgetWithText(FilledButton, 'Transcriberen');
      return button.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(button).onPressed != null;
    });
    await tester.tap(find.text('Transcriberen'));
    await pumpUntil(
      tester,
      () => container.read(tabsProvider).current?.documentNotifier != null,
    );
    expect(engine.receivedDuration, const Duration(seconds: 1));
    final source = container
        .read(tabsProvider)
        .current!
        .documentNotifier!
        .state
        .document!
        .source;
    expect(source, contains('"start_us":1200000'));
    await pumpUntil(tester, () => !File(fileSource.openedPath!).existsSync());
  });
}
