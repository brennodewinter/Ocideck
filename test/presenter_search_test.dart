import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Future<void> _find(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('audience-only surface never opens private search', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: [Slide.create(SlideType.bullets).copyWith(title: 'Publiek')],
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await _find(tester);
    expect(find.byKey(const ValueKey('presenter-search-query')), findsNothing);
    expect(find.textContaining('apart presentatorvenster'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search stays private until explicit show and Escape only closes search',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenPresenter(
            slides: [
              Slide.create(
                SlideType.bullets,
              ).copyWith(title: 'Eerste', advanceDuration: 1),
              Slide.create(SlideType.bullets).copyWith(
                title: 'Tweede',
                bullets: ['uniek zoekwoord', 'tweede zoekwoord'],
                notes: 'geheime notitie',
              ),
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
      await tester.pump();
      calls.clear();
      await _find(tester);
      final field = find.byKey(const ValueKey('presenter-search-query'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'zoekwoord');
      await tester.pumpAndSettle();
      expect(find.textContaining('uniek zoekwoord'), findsWidgets);
      expect(find.text('1/2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      await tester.enterText(field, 'geheime notitie');
      await tester.pumpAndSettle();
      expect(
        find.text('Geen resultaten. Probeer een kortere zoektekst.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      await tester.enterText(field, 'zoekwoord');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(
        calls.where((c) => c.arguments.toString().contains('zoekwoord')),
        isEmpty,
      );
      expect(
        calls.where((c) => c.arguments.toString().contains('geheime notitie')),
        isEmpty,
      );
      expect(
        calls.where((c) => c.arguments.toString().contains('index: 1')),
        isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(find.byType(FullscreenPresenter), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(
        calls.where((c) => c.arguments.toString().contains('index: 1')),
        isEmpty,
      );
      await _find(tester);
      await tester.enterText(field, 'zoekwoord');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toon dia'));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(
        calls.any((c) => c.arguments.toString().contains('index: 1')),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'search excludes skipped and TLP-blocked slides at 200% text size',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1400);
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
      final handle = AudienceWindowHandle(
        WindowController.fromWindowId('test'),
        closeImpl: (_) async {},
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
              Slide.create(
                SlideType.bullets,
              ).copyWith(title: 'niet vindbaar', skipped: true),
              Slide.create(
                SlideType.bullets,
              ).copyWith(title: 'niet vindbaar', tlp: TlpLevel.red),
            ],
            projectPath: null,
            themeProfile: const ThemeProfile(),
            initialIndex: 0,
            audience: handle,
          ),
        ),
      );
      await tester.pump();
      await _find(tester);
      await tester.enterText(
        find.byKey(const ValueKey('presenter-search-query')),
        'vindbaar',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Geen resultaten. Probeer een kortere zoektekst.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await handle.close();
      await _find(tester);
      expect(
        find.byKey(const ValueKey('presenter-search-query')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'rich text and scoped-note matches publish their actual rendered page',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );
      final slide = Slide.create(SlideType.freeMarkdown).copyWith(
        title: 'Lange dia',
        customMarkdown:
            '${List.generate(80, (i) => 'Alinea $i met voldoende tekst voor meerdere pagina’s.').join('\n\n')}\n\nlaatstevindplaats',
        notes: '<!-- ocideck_page:2 -->\nnotitievindplaats',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenPresenter(
            slides: [slide],
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
      calls.clear();
      await _find(tester);
      final field = find.byKey(const ValueKey('presenter-search-query'));
      await tester.enterText(field, 'notitievindplaats');
      await tester.pumpAndSettle();
      expect(
        find.text('Geen resultaten. Probeer een kortere zoektekst.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(
        calls.where((c) => c.arguments.toString().contains('richTextPage: 1')),
        isEmpty,
      );
      await tester.tap(find.text('Toon dia'));
      await tester.pumpAndSettle();
      expect(
        calls.any((c) => c.arguments.toString().contains('richTextPage: 1')),
        isTrue,
      );
      calls.clear();
      await _find(tester);
      await tester.enterText(field, 'laatstevindplaats');
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.text('Toon dia'));
      await tester.pumpAndSettle();
      expect(
        calls.any(
          (c) => RegExp(
            r'richTextPage: [2-9][0-9]*',
          ).hasMatch(c.arguments.toString()),
        ),
        isTrue,
      );
      expect(
        calls.any((c) => c.arguments.toString().contains('vindplaats')),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
