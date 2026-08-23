import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsNotifier> _notifierWith(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final notifier = SettingsNotifier();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Vigilis is een volledig lokaal ingebouwd stijlprofiel', () {
    expect(ThemeProfile.builtIns, contains(ThemeProfile.vigilis));
    expect(ThemeProfile.vigilis.accentColor, '#FFB800');
    expect(ThemeProfile.vigilis.textColor, '#111318');
    expect(
      ThemeProfile.vigilis.logoPath,
      'asset:assets/images/vigilis-logo.png',
    );
  });

  test('bestaande installaties behouden hun eigen profielenlijst', () async {
    final notifier = await _notifierWith({
      'themeProfiles': jsonEncode([
        const ThemeProfile(name: 'Eigen huisstijl').toJson(),
      ]),
      'selectedThemeProfileName': 'Eigen huisstijl',
    });
    // Geen stille injectie van de ingebouwde profielen: opgeslagen prefs
    // winnen altijd.
    expect(notifier.state.themeProfiles, hasLength(1));
    expect(notifier.state.themeProfile.name, 'Eigen huisstijl');
  });

  test(
    'legacy enkelvoudig themeProfile migreert zonder LibreKAT-injectie',
    () async {
      final notifier = await _notifierWith({
        'themeProfile': jsonEncode(
          const ThemeProfile(name: 'Oud profiel').toJson(),
        ),
      });
      expect(notifier.state.themeProfiles, hasLength(1));
      expect(notifier.state.themeProfile.name, 'Oud profiel');
    },
  );

  testWidgets('het gebundelde LibreKAT-logo rendert op een slide', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.title,
    ).copyWith(title: 'LibreKAT', showLogo: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: ThemeProfile.libreKat,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final assetImages = tester
        .widgetList<Image>(find.byType(Image))
        .where(
          (w) =>
              w.image is ResizeImage &&
              (w.image as ResizeImage).imageProvider is AssetImage &&
              ((w.image as ResizeImage).imageProvider as AssetImage)
                      .assetName ==
                  'assets/images/librekat-logo.png',
        );
    expect(
      assetImages,
      isNotEmpty,
      reason: 'asset:-logo moet als AssetImage renderen',
    );
  });
}
