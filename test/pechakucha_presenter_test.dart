import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/presentation_timing.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host({
  bool rehearsalMode = false,
  PresentationTimingConfig timing =
      const PresentationTimingConfig.pechaKuchaPreset(),
}) {
  final slides = [
    Slide.create(SlideType.bullets).copyWith(title: 'Eerste'),
    Slide.create(SlideType.bullets).copyWith(title: 'Tweede'),
  ];
  return MaterialApp(
    localizationsDelegates: const [
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: FullscreenPresenter(
      slides: slides,
      projectPath: null,
      themeProfile: const ThemeProfile(),
      initialIndex: 1,
      presentationTiming: timing,
      rehearsalMode: rehearsalMode,
    ),
  );
}

Slide _currentSlide(WidgetTester tester) => tester
    .widget<SlidePreviewWidget>(find.byType(SlidePreviewWidget).first)
    .slide;

void main() {
  testWidgets('PechaKucha starts its countdown when presentation mode opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('3'), findsOneWidget);
    expect(find.text('Start aftellen'), findsNothing);
    expect(_currentSlide(tester).title, 'Eerste');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_currentSlide(tester).title, 'Eerste');
  });

  testWidgets(
    'countdown does not consume slide time and space pauses rehearsal',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(rehearsalMode: true));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(_currentSlide(tester).title, 'Eerste');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('GEPAUZEERD'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_currentSlide(tester).title, 'Eerste');
    },
  );

  testWidgets('Ignite start eveneens meteen met aftellen', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(timing: const PresentationTimingConfig.ignitePreset()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('3'), findsOneWidget);
    expect(find.text('Start aftellen'), findsNothing);
    expect(_currentSlide(tester).title, 'Eerste');
  });
}
