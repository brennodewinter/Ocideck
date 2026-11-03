import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Future<void> _host(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: FullscreenPresenter(
        slides: [
          Slide.create(SlideType.bullets).copyWith(title: 'Eerste'),
          Slide.create(SlideType.bullets).copyWith(title: 'Tweede'),
        ],
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
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1400, 1000),
    const Size(800, 600),
    const Size(480, 800),
  ]) {
    testWidgets('cockpit fits $size at 200% text', (tester) async {
      await _host(tester, size);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final size in [const Size(800, 600), const Size(480, 800)]) {
    testWidgets('private search fits $size at 200% text', (tester) async {
      await _host(tester, size);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final query = find.byKey(const ValueKey('presenter-search-query'));
      expect(query, findsOneWidget);
      await tester.enterText(query, 'Tweede');
      await tester.pumpAndSettle();
      final show = find.text('Toon dia');
      expect(tester.getBottomRight(show).dy, lessThan(size.height));
      expect(tester.getTopLeft(show).dx, greaterThanOrEqualTo(0));
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(query, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
