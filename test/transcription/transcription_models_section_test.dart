// De modelbeheer-sectie onder de Transcriptie-kaart (#2512): elke rij
// spiegelt wat op schijf staat — Binnenhalen start de download, de
// vuilnisbak verwijdert het model weer.
//
// Werkvorm: de provider-calls lopen binnen `tester.runAsync`. In de
// fake-async zone van testWidgets resolven `dart:io`-futures niet, dus
// een knopdruk daar zou halverwege de eerste bestands-await blijven
// steken; `runAsync` is daarvoor gemaakt.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/model_download_io.dart';
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:ocideck/state/transcription_model_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/transcription_models_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temp;
  late _SpyStore store;

  final bytes = List<int>.generate(64, (i) => i);
  final model = WhisperModel(
    id: 'test',
    fileName: 'ggml-test.bin',
    sha256: sha256.convert(bytes).toString(),
    downloadBytes: bytes.length,
    diskBytes: bytes.length,
    tier: 'light',
  );

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('models_section_');
    store = _SpyStore(root: temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Widget app() => ProviderScope(
    overrides: [
      transcriptionModelStoreProvider.overrideWithValue(store),
      transcriptionModelDownloaderProvider.overrideWithValue(
        createTestModelDownloader(
          (url) async => ModelFetchResult(
            statusCode: 200,
            contentLength: bytes.length,
            body: Stream.value(bytes),
          ),
        ),
      ),
      whisperModelCatalogProvider.overrideWithValue([model]),
      transcriptionEngineProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: TranscriptionModelsSection()),
    ),
  );

  TranscriptionModelManager manager(WidgetTester tester) {
    final ctx = tester.element(find.byType(TranscriptionModelsSection));
    return ProviderScope.containerOf(
      ctx,
    ).read(transcriptionModelManagerProvider.notifier);
  }

  Future<void> refresh(WidgetTester tester) =>
      tester.runAsync(() => manager(tester).refresh());

  testWidgets('een afwezig model toont rij, toestand en Binnenhalen-knop', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await refresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('Whisper test'), findsOneWidget);
    expect(find.text('Niet geïnstalleerd'), findsOneWidget);
    expect(find.text('Binnenhalen'), findsOneWidget);
    expect(find.textContaining('Lokaal spraakmodel'), findsOneWidget);
    // Engine is null → de statusregel valt weg.
    expect(find.textContaining('Engine'), findsNothing);
  });

  testWidgets('de Binnenhalen-knop start echt de download', (tester) async {
    await tester.pumpWidget(app());
    await refresh(tester);
    await tester.pumpAndSettle();
    final before = store.modelPathCalls;
    await tester.tap(find.text('Binnenhalen'));
    await tester.pump();
    // De synchrone helft van download() is bewijsbaar: het doelpad wordt
    // opgevraagd en de spiegel toont "bezig".
    expect(store.modelPathCalls, greaterThan(before));
    final ctx = tester.element(find.byType(TranscriptionModelsSection));
    final mirror = ProviderScope.containerOf(
      ctx,
    ).read(transcriptionModelManagerProvider);
    expect(mirror[model.id]?.downloading, isTrue);
  });

  testWidgets('voltooide download → Geïnstalleerd; vuilnis → weer afwezig', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.runAsync(() => manager(tester).download(model));
    await tester.pumpAndSettle();
    expect(find.text('Geïnstalleerd'), findsOneWidget);
    expect(File('${temp.path}/ggml-test.bin').existsSync(), isTrue);

    await tester.runAsync(() => manager(tester).delete(model));
    await tester.pumpAndSettle();
    expect(find.text('Niet geïnstalleerd'), findsOneWidget);
    expect(File('${temp.path}/ggml-test.bin').existsSync(), isFalse);
  });

  testWidgets('een model op schijf opent als Geïnstalleerd', (tester) async {
    File('${temp.path}/ggml-test.bin').writeAsBytesSync(bytes);
    await tester.pumpWidget(app());
    await refresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('Geïnstalleerd'), findsOneWidget);
  });
}

/// Telt `modelPath`-aanroepen zodat de knop→manager→store-keten bewijsbaar
/// is zonder dat de (fake-zone-)download zelf hoeft door te lopen.
class _SpyStore extends IoModelStore {
  _SpyStore({super.root});

  var modelPathCalls = 0;

  @override
  Future<ModelStorePath> modelPath(WhisperModel model) {
    modelPathCalls++;
    return super.modelPath(model);
  }
}
