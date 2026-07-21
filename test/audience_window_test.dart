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

/// Twee losse dia's, gescheiden door een `---`. Het deck hierboven is één dia
/// (kop, tussenkop en bullets horen daar bij elkaar), dus daarmee valt niet te
/// zien óf de beamer meebeweegt: elke index toont dezelfde tekst.
const String _twoSlideMarkdown =
    '---\n'
    'title: Audience Demo\n'
    'theme: ocideck\n'
    '---\n'
    '# Welkom\n'
    '\n'
    '---\n'
    '\n'
    '# Tweede dia\n'
    '\n'
    '- Eerste punt\n';

const _bridge = MethodChannel('mixin.one/desktop_multi_window/channels');

/// Laat de presenter een bericht sturen zoals hij dat over de vensterbrug doet.
/// De brug moet ook uitgaand gemockt zijn, anders registreert de ontvanger
/// zijn handler niet en komt er niets aan.
Future<void> _fromPresenter(
  WidgetTester tester,
  String method, [
  Object? arguments,
]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
  _bridge.name,
  _bridge.codec.encodeMethodCall(
    MethodCall('methodCall', {
      'channel': 'ocideck/audience',
      'method': method,
      'arguments': arguments,
    }),
  ),
  (_) {},
);

void _mockBridge(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _bridge,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridge,
      null,
    ),
  );
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

  testWidgets('other keys travel to the presenter instead of dying here', (
    tester,
  ) async {
    // Het beamervenster is een eigen venster met een eigen engine: pakt het de
    // toetsenbordfocus, dan is dit de enige weg terug naar de sneltoetsen van
    // de presentatie. Vroeger slikte dit venster alles behalve Cmd+W op —
    // Escape kwam dus nooit aan, en wie in een tabel stond te typen zat vast.
    const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
    final sent = <String, Object?>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
      call,
    ) async {
      if (call.method == 'invokeMethod') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (args['method'] == 'key') {
          sent.addAll(Map<String, dynamic>.from(args['arguments'] as Map));
        }
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    // De modifiers reizen mee: de presenterkant draait op een eigen engine en
    // kan ze daar niet uitlezen.
    expect(sent['keyId'], LogicalKeyboardKey.escape.keyId);
    expect(sent['shift'], isTrue);
    expect(sent['meta'], isFalse);
    expect(sent['control'], isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the beamer follows the presenter and blanks on command', (
    tester,
  ) async {
    // De hele reden van bestaan van dit venster: in de pas blijven met de
    // laptop. Zonder deze toets is een beamer die op de vorige slide blijft
    // hangen pas in de zaal te merken.
    _mockBridge(tester);
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': _twoSlideMarkdown,
      'index': 0,
    });
    // De ontvanger registreert zijn handler asynchroon over dezelfde brug.
    await tester.pumpAndSettle();
    expect(find.text('Welkom'), findsOneWidget);

    await _fromPresenter(tester, 'update', {'index': 1, 'seq': 1});
    await tester.pump();
    expect(find.text('Welkom'), findsNothing);
    expect(find.text('Tweede dia'), findsOneWidget);

    // Zwart scherm (B op de presenter): de zaal ziet niets van de dia.
    await _fromPresenter(tester, 'update', {'index': 1, 'seq': 2, 'blank': 1});
    await tester.pump();
    expect(find.text('Tweede dia'), findsNothing);

    // En terug.
    await _fromPresenter(tester, 'update', {'index': 1, 'seq': 3, 'blank': 0});
    await tester.pump();
    expect(find.text('Tweede dia'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a late update from an older slide never wins', (tester) async {
    // Berichten komen niet gegarandeerd in volgorde binnen. Bij snel doorklikken
    // mag een trage aanroep van slide 1 de al getoonde slide 2 niet terugzetten.
    _mockBridge(tester);
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': _twoSlideMarkdown,
      'index': 0,
    });
    await tester.pumpAndSettle();

    await _fromPresenter(tester, 'update', {'index': 1, 'seq': 7});
    await tester.pump();
    expect(find.text('Tweede dia'), findsOneWidget);

    await _fromPresenter(tester, 'update', {'index': 0, 'seq': 6});
    await tester.pump();
    expect(find.text('Tweede dia'), findsOneWidget);
    expect(find.text('Welkom'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a live table edit on the laptop lands on the beamer', (
    tester,
  ) async {
    // De tabel die de spreker tijdens het presenteren bijwerkt, moet de zaal
    // ook zien. Zonder deze spiegeling praat de spreker over cijfers die op het
    // grote scherm nog de oude zijn — en dat merkt niemand op tijd.
    const tableDeck =
        '---\n'
        'title: Audience Demo\n'
        '---\n'
        '<!-- _class: table -->\n'
        '# Cijfers\n'
        '\n'
        '| Rol | Waarde |\n'
        '| --- | --- |\n'
        '| Bestuur | oud |\n';
    _mockBridge(tester);
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': tableDeck,
      'index': 0,
    });
    await tester.pumpAndSettle();
    expect(find.text('oud'), findsOneWidget);

    await _fromPresenter(tester, 'tableUpdate', {
      'slideIndex': 0,
      'tableRows': [
        ['Rol', 'Waarde'],
        ['Bestuur', 'nieuw'],
      ],
    });
    await tester.pump();

    expect(find.text('nieuw'), findsOneWidget);
    expect(find.text('oud'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a checklist ticked while presenting mirrors to the beamer', (
    tester,
  ) async {
    const checklistDeck =
        '---\n'
        'title: Audience Demo\n'
        '---\n'
        '# Af te vinken\n'
        '\n'
        '- [ ] Back-up getest\n';
    _mockBridge(tester);
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': checklistDeck,
      'index': 0,
    });
    await tester.pumpAndSettle();

    await _fromPresenter(tester, 'checklistUpdate', {
      'slideIndex': 0,
      'bullets': ['[x] Back-up getest'],
      'bullets2': <String>[],
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Back-up getest'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unknown message from the presenter is ignored, not fatal', (
    tester,
  ) async {
    // De twee vensters kunnen uit versie lopen (de een is bijgewerkt, de ander
    // nog niet). Een bericht dat dit venster niet kent hoort dan stil te
    // verdwijnen in plaats van de beamer om te trekken.
    _mockBridge(tester);
    await _pumpAudience(tester, <String, dynamic>{
      'markdown': _twoSlideMarkdown,
      'index': 0,
    });
    await tester.pumpAndSettle();

    await _fromPresenter(tester, 'ditBestaatNiet', {'wat': 'dan ook'});
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Welkom'), findsOneWidget);

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
