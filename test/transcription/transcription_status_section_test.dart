// De statusmatrix uit #2514 toont feiten, geen beloftes: elke rij is de
// waarde die het platform passief rapporteert, en een niet-geregistreerde
// bron is een zichtbaar "nog niet", geen lege plek (§5.1).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:ocideck/state/transcription_model_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/transcription_status_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_capture_source.dart';

void main() {
  late Directory temp;

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
    temp = Directory.systemTemp.createTempSync('status_section_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Widget app({
    Map<CaptureSourceKind, CaptureSource> sources = const {},
    bool realEngine = false,
  }) => ProviderScope(
    overrides: [
      transcriptionModelStoreProvider.overrideWithValue(
        IoModelStore(root: temp, candidateRoots: const []),
      ),
      whisperModelCatalogProvider.overrideWithValue([model]),
      if (!realEngine) transcriptionEngineProvider.overrideWith((ref) => null),
      captureSourcesProvider.overrideWithValue(sources),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(child: TranscriptionStatusSection()),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    // De io-probe en modelstore doen echte dart:io-aanroepen — die horen
    // in de echte event loop, niet in de fake-async zone van pump.
    final ctx = tester.element(find.byType(TranscriptionStatusSection));
    await tester.runAsync(
      () => ProviderScope.containerOf(
        ctx,
      ).read(transcriptionModelManagerProvider.notifier).refresh(),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('platform, route en engine benoemen de echte toestand', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    // De io-probe op de test-VM rapporteert een echt OS + architectuur.
    final platform = switch (Platform.operatingSystem) {
      'macos' => 'macOS',
      'linux' => 'Linux',
      'windows' => 'Windows',
      final other => other,
    };
    expect(find.textContaining('$platform · '), findsOneWidget);
    expect(
      find.text('Lokaal — er vertrekt geen audio van dit apparaat'),
      findsOneWidget,
    );
    expect(find.text('geen engine beschikbaar'), findsOneWidget);
    expect(find.textContaining('niet geïnstalleerd'), findsOneWidget);
  });

  testWidgets('een leeg bronnenregister toont "nog niet" per bronsoort', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    for (final label in [
      'Bestaand audio/videobestand',
      'Microfoon',
      'Systeem-/appgeluid',
      'Microfoon + systeemgeluid',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // callAudio staat bewust buiten de matrix: hij is sessie-scoped,
    // geen platformbron (#2529).
    expect(
      find.text('nog niet beschikbaar op dit platform'),
      findsNWidgets(
        CaptureSourceKind.values
            .where((k) => k != CaptureSourceKind.callAudio)
            .length,
      ),
    );
    // De permissierij claimt niets dat nog niet bewezen is.
    expect(
      find.textContaining('Onbekend — pas bij de eerste opname'),
      findsOneWidget,
    );
  });

  testWidgets('een geregistreerde bron toont zijn probe-uitslag', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        sources: {
          CaptureSourceKind.microphone: FakeCaptureSource(
            availability: CaptureAvailability.tryAfterPermission,
          ),
        },
      ),
    );
    await settle(tester);

    expect(
      find.text('waarschijnlijk — toestemming volgt bij eerste gebruik'),
      findsOneWidget,
    );
    // De overige platformsoorten blijven eerlijk "nog niet" (callAudio
    // staat buiten de matrix — hij is sessie-scoped, #2529).
    expect(
      find.text('nog niet beschikbaar op dit platform'),
      findsNWidgets(CaptureSourceKind.values.length - 2),
    );
  });

  testWidgets('serverroute met actief profiel toont de server als route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      transcriptionRouteKey: 'server',
      asrServerProfileKey: jsonEncode(
        const AsrServerProfile(
          enabled: true,
          mode: AsrServerMode.loopback,
          baseUrl: 'http://127.0.0.1:8080',
          name: 'kelder',
        ).toJson(),
      ),
    });
    await tester.pumpWidget(app(realEngine: true));
    await settle(tester);

    expect(find.text('Eigen ASR-server (kelder)'), findsOneWidget);
    // De echte engine is een serverengine: batch only, geen live-claim.
    expect(find.text('server — kelder'), findsOneWidget);
    expect(
      find.text('batchtranscriptie; live-tekst kan deze route niet'),
      findsOneWidget,
    );
  });

  testWidgets('serverroute zónder profiel valt terug op lokaal beeld', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({transcriptionRouteKey: 'server'});
    await tester.pumpWidget(app(realEngine: true));
    await settle(tester);

    // Zonder bruikbaar profiel kiest de provider de veilige richting.
    expect(
      find.text('Lokaal — er vertrekt geen audio van dit apparaat'),
      findsOneWidget,
    );
  });
}
