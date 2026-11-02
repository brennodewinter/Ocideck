import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _host(WidgetTester tester, List<Slide> slides) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    bridge,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridge,
      null,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: FullscreenPresenter(
        slides: slides,
        projectPath: null,
        themeProfile: const ThemeProfile(),
        initialIndex: 0,
        audience: AudienceWindowHandle(
          WindowController.fromWindowId('test'),
          closeImpl: (_) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      '$platform native find and select-all keep editing shortcuts working',
      (tester) async {
        await _host(tester, [
          Slide.create(SlideType.bullets).copyWith(title: 'Zoekbare dia'),
        ]);
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await _chord(tester, modifier, LogicalKeyboardKey.keyF);
        final field = find.byKey(const ValueKey('presenter-search-query'));
        expect(field, findsOneWidget);
        await tester.enterText(field, 'voorbeeldquery');
        await _chord(tester, modifier, LogicalKeyboardKey.keyA);
        expect(
          tester.widget<TextField>(field).controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 14),
        );
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'presenter search recomputes for input, notes and content, not selection',
    (tester) async {
      debugPresenterSearchRecomputations = 0;
      final slides = [
        Slide.create(SlideType.bullets).copyWith(title: 'zoekwoord eerste'),
        Slide.create(SlideType.bullets).copyWith(title: 'zoekwoord tweede'),
      ];
      await _host(tester, slides);
      await _chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      );
      final field = find.byKey(const ValueKey('presenter-search-query'));
      await tester.enterText(field, 'zoekwoord');
      await tester.pumpAndSettle();
      final afterQuery = debugPresenterSearchRecomputations;
      expect(find.text('1/2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(debugPresenterSearchRecomputations, afterQuery);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(debugPresenterSearchRecomputations, afterQuery + 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      slides[1] = slides[1].copyWith(title: 'verdwenen');
      final beforeReopen = debugPresenterSearchRecomputations;
      await _chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      );
      expect(find.text('1/1'), findsOneWidget);
      expect(debugPresenterSearchRecomputations, beforeReopen + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
