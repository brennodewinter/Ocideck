// Real provider and ASR with production widgets in Flutter's test harness.
// This is deliberately not presented as a packaged release / OS dialog test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/transcription/recording_staging_io.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/editors/video_slide_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../test/support/pump_until.dart';

void main() {
  final proof = <Object?>[];
  late Directory temporary;
  late ProviderContainer container;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ocideck-source-ui-');
    AppLocalizations.setActiveLanguageCode('nl');
    // Standalone live test target outside test/, isolated from user settings.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'languageCode': 'nl',
      'transcriptionModuleEnabled': true,
      'allowRemoteMedia': true,
      'storageConnections': jsonEncode([
        LocalConnection(
          id: 'probe',
          name: 'Probe',
          path: temporary.path,
        ).toJson(),
      ]),
      'transcriptionRoute': 'server',
      'asrServerProfile': jsonEncode(
        const AsrServerProfile(
          enabled: true,
          mode: AsrServerMode.loopback,
          baseUrl: 'http://127.0.0.1:8093',
          batchProtocol: AsrBatchProtocol.ocideckV1,
        ).toJson(),
      ),
    });
  });
  tearDown(() async => temporary.delete(recursive: true));
  tearDownAll(() async {
    final output = Platform.environment['OCIDECK_YOUTUBE_UI_RESULT'];
    if (output == null) throw StateError('explicit proof output required');
    await File(output).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'scope': 'macOS ARM64 production widgets, native source and ASR HTTP clients in Flutter test harness; not packaged release UI', 'source_revision': Platform.environment['OCIDECK_SOURCE_REVISION'], 'flows': proof})}\n',
    );
  });

  Future<void> boot(WidgetTester tester, {bool videoEditor = false}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final video = Slide.create(SlideType.video).copyWith(
      title: 'Source probe',
      videoPath: 'https://youtu.be/M7lc1UVf-VE',
      videoStartMs: 10000,
      videoEndMs: 35000,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryServiceProvider.overrideWith((ref) {
            final service = RecoveryService(baseDir: temporary);
            ref.onDispose(() => unawaited(service.endSession()));
            return service;
          }),
          recordingStagingProvider.overrideWithValue(
            IoRecordingStaging(baseDir: Directory('${temporary.path}/staging')),
          ),
        ],
        child: videoEditor
            ? MaterialApp(
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: VideoSlideEditor(
                    slide: video,
                    onUpdate: (_) {},
                    imageService: ImageService(),
                  ),
                ),
              )
            : const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(videoEditor ? VideoSlideEditor : AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Original',
            slides: [
              Slide.create(SlideType.title).copyWith(
                title: 'Source probe',
                customMarkdown: '[Source](https://youtu.be/M7lc1UVf-VE)',
              ),
            ],
          ),
        );
    await tester.pumpAndSettle();
    // Flutter test binding otherwise installs a deliberately rejecting HTTP fake.
    HttpOverrides.global = null;
  }

  Future<void> importMenu(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is PopupMenuItem),
        matching: find.byIcon(Icons.file_upload_outlined),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> captions(WidgetTester tester, String entry) async {
    final before = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck;
    await tester.enterText(
      find.byKey(const ValueKey('youtube-source-endpoint')),
      'http://127.0.0.1:8866',
    );
    await tester.tap(find.text('Video-informatie ophalen'));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('youtube-caption-track'))
          .evaluate()
          .isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    await tester.tap(find.text('Ondertitels overnemen'));
    await pumpUntil(
      tester,
      () => container.read(tabsProvider).current?.documentNotifier != null,
      timeout: const Duration(seconds: 60),
    );
    final source = container
        .read(tabsProvider)
        .current!
        .documentNotifier!
        .currentState
        .document!
        .source;
    expect(source, contains('M7lc1UVf-VE'));
    expect(source, contains('Handmatige ondertitels'));
    expect(
      container.read(tabsProvider).tabs.first.deckNotifier.currentState.deck,
      same(before),
    );
    proof.add({
      'entry': entry,
      'caption_document_sha256': sha256
          .convert(
            utf8.encode(
              source.replaceAll(
                RegExp(r'Opgenomen: .*? · Bron:'),
                'Opgenomen: PROCESSING_DATE · Bron:',
              ),
            ),
          )
          .toString(),
      'original_deck_unchanged': true,
    });
    return source;
  }

  testWidgets(
    'URL open, deck Markdown link and video editor use real captions',
    (tester) async {
      await boot(tester);
      await importMenu(tester);
      await tester.tap(find.text('Openen via URL…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'https://youtu.be/M7lc1UVf-VE?list=discarded',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
      await tester.pumpAndSettle();
      await captions(tester, 'URL open');

      await tester.pumpWidget(const SizedBox());
      await boot(tester);
      await importMenu(tester);
      await tester.tap(find.text('YouTube-video transcriberen…'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Dia 1 · M7lc1UVf-VE'));
      await tester.pumpAndSettle();
      await captions(tester, 'deck Markdown link');

      await tester.pumpWidget(const SizedBox());
      await boot(tester, videoEditor: true);
      await tester.tap(find.text('YouTube-video transcriberen…'));
      await tester.pumpAndSettle();
      await captions(tester, 'video slide editor');
      expect(
        proof.map((flow) => (flow as Map)['caption_document_sha256']).toSet(),
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
