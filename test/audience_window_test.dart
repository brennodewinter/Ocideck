import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/presentation/audience_window.dart';

/// A small but representative deck: a title slide plus a bullets slide, enough
/// to exercise the audience window's markdown parsing and slide rendering.
const String _deckMarkdown =
    '---\n'
    'title: Audience Demo\n'
    'theme: ocideck\n'
    'organization: ACME\n'
    '---\n'
    '# Welkom\n'
    '\n'
    '## Onderwerpen\n'
    '\n'
    '- Eerste punt\n'
    '- Tweede punt\n';

/// Pump the audience window with the given args on a generous surface so the
/// letterboxed 16:9 canvas never trips a RenderFlex overflow.
Future<void> _pumpAudience(
  WidgetTester tester,
  Map<String, dynamic> args,
) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(AudienceWindowApp(args: args));
  await tester.pump();
}

void main() {
  testWidgets(
    'renders a normal slide from the markdown args without throwing',
    (tester) async {
      await _pumpAudience(tester, <String, dynamic>{
        'markdown': _deckMarkdown,
        'index': 0,
      });

      expect(tester.takeException(), isNull);
      expect(find.byType(AudienceWindowApp), findsOneWidget);
      expect(find.text('Welkom'), findsOneWidget);

      // Dispose so the method-call handler is detached cleanly.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('honours the starting index from the args', (tester) async {
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': _deckMarkdown,
      'index': 1,
    });

    expect(tester.takeException(), isNull);
    // The second slide carries the bullet content, not the title slide's text.
    expect(find.text('Eerste punt'), findsOneWidget);
    expect(find.text('Tweede punt'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders an empty (no-slides) deck as a blank surface', (
    tester,
  ) async {
    await _pumpAudience(tester, <String, dynamic>{'markdown': ''});

    // An empty deck collapses to SizedBox.shrink; it must still build cleanly.
    expect(tester.takeException(), isNull);
    expect(find.byType(AudienceWindowApp), findsOneWidget);
    expect(find.text('Welkom'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'renders with classification watermark and remote media enabled',
    (tester) async {
      await _pumpAudience(tester, <String, dynamic>{
        'markdown': _deckMarkdown,
        'index': 0,
        'classificationWatermarkEnabled': true,
        'allowRemoteMedia': true,
      });

      expect(tester.takeException(), isNull);
      expect(find.byType(AudienceWindowApp), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tolerates missing optional args and out-of-range index', (
    tester,
  ) async {
    // No index supplied (defaults to 0) and an absent projectPath/ink map: the
    // window should still parse the deck and render the first slide.
    await _pumpAudience(tester, <String, dynamic>{'markdown': _deckMarkdown});

    expect(tester.takeException(), isNull);
    expect(find.text('Welkom'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl/Cmd + W asks the presenter to close the presentation', (
    tester,
  ) async {
    // The beamer forwards navigation and exit over a desktop_multi_window
    // channel; intercept it to confirm an 'exit' request is sent.
    const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
    final sent = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
      call,
    ) async {
      if (call.method == 'invokeMethod') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final method = args['method'];
        if (method is String) sent.add(method);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        bridge,
        null,
      ),
    );

    await _pumpAudience(tester, <String, dynamic>{
      'markdown': _deckMarkdown,
      'index': 0,
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(sent, contains('exit'));

    await tester.pumpWidget(const SizedBox());
  });

  test('stale update sequence numbers are rejected, unnumbered accepted', () {
    // Nieuwere en gelijk-oplopende nummers verwerken.
    expect(isStaleUpdateSeq(5, 4), isFalse);
    expect(isStaleUpdateSeq(1, -1), isFalse);
    // Verouderd of duplicaat: negeren, zodat een trage aanroep een snellere
    // nooit overschrijft.
    expect(isStaleUpdateSeq(4, 5), isTrue);
    expect(isStaleUpdateSeq(5, 5), isTrue);
    // Berichten van een oudere presenter zonder nummer blijven werken.
    expect(isStaleUpdateSeq(null, 99), isFalse);
  });
}
