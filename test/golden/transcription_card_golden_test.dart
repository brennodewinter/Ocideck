@Tags(['golden'])
library;

// De Transcriptie-modulekaart uit #2514 als pixelregressie: de kaart is
// lang (route, statusmatrix, modellen, serverprofiel) en moet in beide
// thema's en in de uit-toestand leesbaar blijven.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:ocideck/state/transcription_model_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/settings/transcription_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_until.dart';

const _surfaceKey = ValueKey('transcription-card-golden-surface');

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required bool moduleOn,
}) async {
  const size = Size(760, 1400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => AppTheme.isDark = false);
  AppTheme.isDark = dark;

  SharedPreferences.setMockInitialValues({
    transcriptionModuleEnabledKey: moduleOn,
  });
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );

  final temp = Directory.systemTemp.createTempSync('card_golden_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final bytes = List<int>.generate(64, (i) => i);
  final model = WhisperModel(
    id: 'test',
    fileName: 'ggml-test.bin',
    sha256: sha256.convert(bytes).toString(),
    downloadBytes: bytes.length,
    diskBytes: bytes.length,
    tier: 'light',
  );

  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transcriptionModelStoreProvider.overrideWithValue(
          IoModelStore(root: temp),
        ),
        whisperModelCatalogProvider.overrideWithValue([model]),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size, disableAnimations: true),
          child: Scaffold(
            body: RepaintBoundary(
              key: _surfaceKey,
              child: ColoredBox(
                color: baseTheme.colorScheme.surfaceContainerLow,
                child: const SingleChildScrollView(
                  child: TranscriptionModuleCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // De io-probe en modelstore doen echte dart:io-calls — die lopen in de
  // echte event loop, niet in de fake-async zone. De plaat mag pas als de
  // tussenstatus ("detecteren…", "controleren…") weg is; een vaste duur
  // vangt die soms nog en wijkt dan af onder een volle suite.
  final ctx = tester.element(find.byType(TranscriptionModuleCard));
  await tester.runAsync(
    () => ProviderScope.containerOf(
      ctx,
    ).read(transcriptionModelManagerProvider.notifier).refresh(),
  );
  await pumpUntil(
    tester,
    () =>
        find.textContaining('detecteren').evaluate().isEmpty &&
        find.textContaining('controleren').evaluate().isEmpty,
    reason: 'de statusmatrix bleef op een tussenstatus hangen',
  );

  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('transcriptiekaart volgt licht en donker profiel, module uit', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    for (final dark in [false, true]) {
      await _match(
        tester,
        name: 'transcription_card_${dark ? 'dark' : 'light'}',
        dark: dark,
        moduleOn: false,
      );
    }
  });

  testWidgets('transcriptiekaart met module aan zonder uit-uitleg', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    await _match(
      tester,
      name: 'transcription_card_on',
      dark: false,
      moduleOn: true,
    );
  });
}
