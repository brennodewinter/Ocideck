import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  testWidgets('capture authentic cockpit for the documentation', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf')))
        .load();

    final slide = Slide.create(SlideType.cockpit).copyWith(
      title: 'Statusdashboard weerbaarheid',
      customMarkdown: CockpitSpec.samplePreset().toBlock(),
    );
    const captureKey = ValueKey('cockpit-documentation-capture');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: captureKey,
          child: SlidePreviewWidget(
            slide: slide,
            themeProfile: const ThemeProfile(fontFamily: 'Roboto'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('../docs/images/cockpit-dashboard.png'),
    );
  });
}
