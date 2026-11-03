import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/theme/app_theme.dart';
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

Future<void> _host(
  WidgetTester tester,
  List<Slide> slides, {
  ThemeData? theme,
}) async {
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
      theme: theme,
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
  for (final profile in [
    AppAppearanceProfile.basic,
    AppAppearanceProfile.dark,
    AppAppearanceProfile.basic.copyWith(
      name: 'Eigen zoekstijl',
      primaryColor: '#472D73',
      accentColor: '#BD325A',
      surfaceColor: '#FFF6E0',
      textColor: '#234631',
      mutedTextColor: '#765630',
      fontFamily: 'Lora',
    ),
  ]) {
    testWidgets('privézoeken behoudt gekozen appstijl ${profile.name}', (
      tester,
    ) async {
      final theme = AppTheme.fromProfile(profile);
      final palette = AppPalette.of(theme);
      await _host(tester, [
        Slide.create(SlideType.bullets).copyWith(title: 'zoekanker eerste'),
        Slide.create(SlideType.bullets).copyWith(title: 'zoekanker tweede'),
      ], theme: theme);
      await _chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      );
      final field = find.byKey(const ValueKey('presenter-search-query'));
      await tester.enterText(field, 'zoekanker');
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(field)).brightness, theme.brightness);
      expect(
        Theme.of(tester.element(field)).dialogTheme.backgroundColor,
        AppTheme.parseHexColor(profile.surfaceColor),
      );
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      final snippets = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(RichText),
            ),
          )
          .where((text) => text.text.toPlainText() == 'zoekanker eerste');
      expect(snippets, isNotEmpty);
      for (final snippet in snippets) {
        expect(snippet.text.style?.color, palette.mutedText);
        expect(snippet.text.style?.fontFamily, profile.fontFamily);
      }
      final action = find.ancestor(
        of: find.text('Toon dia'),
        matching: find.byType(ElevatedButton),
      );
      expect(action, findsOneWidget);
      final actionText = tester.widget<RichText>(
        find.descendant(of: action, matching: find.byType(RichText)).first,
      );
      expect(actionText.text.style?.fontFamily, profile.fontFamily);
      final material = tester.widget<Material>(
        find.descendant(of: action, matching: find.byType(Material)).first,
      );
      expect(material.color, AppTheme.parseHexColor(profile.accentColor));
      expect(
        material.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

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
