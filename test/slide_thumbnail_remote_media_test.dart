import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De rail-thumbnail is de énige slide-preview die je tijdens het bewerken ziet.
/// Hij gaf `allowRemoteMedia` niet door aan SlidePreviewWidget, waardoor die
/// terugviel op de fail-closed standaard `false`: een online video/afbeelding
/// meldde "Online media staat uit" ook als de instelling aan stond.
void main() {
  Future<void> pumpRail(
    WidgetTester tester, {
    required bool allowRemoteMedia,
  }) async {
    SharedPreferences.setMockInitialValues({
      'allowRemoteMedia': allowRemoteMedia,
    });

    final slide = Slide.create(SlideType.video).copyWith(
      videoPath: 'https://dewinter.com/img/video/ik-zal-je-leren-toxisch.mp4',
      title: 'Online clip',
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // De instellingen laden asynchroon uit de prefs; wacht tot de vlag staat.
    await tester.runAsync(() async {
      container.read(settingsProvider);
      for (var i = 0; i < 20; i++) {
        if (container.read(settingsProvider).allowRemoteMedia ==
            allowRemoteMedia) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 260,
              child: SlideThumbnail(
                slide: slide,
                index: 0,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('rail thumbnail blocks online media when the setting is off', (
    tester,
  ) async {
    await pumpRail(tester, allowRemoteMedia: false);
    expect(find.text('Online media staat uit'), findsOneWidget);
  });

  testWidgets('rail thumbnail honours the setting when online media is on', (
    tester,
  ) async {
    await pumpRail(tester, allowRemoteMedia: true);
    expect(find.text('Online media staat uit'), findsNothing);
  });
}
