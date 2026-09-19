@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/presentation_timing.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/presentation_info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceKey = ValueKey('presentation-format-picker-golden-surface');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('grafische presentatievormkiezer', (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final baseTheme = AppTheme.light;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: _surfaceKey,
              child: const PresentationInfoDialog(
                deck: Deck(
                  title: 'Twintig beelden, één ritme',
                  presentationTiming:
                      PresentationTimingConfig.pechaKuchaPreset(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/presentation_format_picker.png'),
    );
  });
}
