import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// Een schermenlijst die de test bepaalt, in plaats van de schermen van deze
/// machine.
class _FakeScreens extends ScreenRetrieverPlatform {
  _FakeScreens(this.displays);

  final List<Display> displays;
  int gevraagd = 0;

  @override
  Future<List<Display>> getAllDisplays() async {
    gevraagd++;
    return displays;
  }
}

/// Van scherm wisselen tijdens het presenteren
/// (`widgets/presentation/parts/presenter_displays.dart`).
///
/// Dit bestand stond op 2 van 33 regels omdat het op twee desktop-plugins
/// leunt die onder `flutter test` niet bestaan. Ze zijn hier allebei vervangen
/// door een dubbel: de schermenlijst via de platform-interface, het venster via
/// zijn methodekanaal. Wat overblijft is het gedrag dat ertoe doet — dat de
/// knop er alleen ís bij meer dan één scherm, dat wisselen naar het ándere
/// scherm gaat, en dat een mislukking niet stil blijft.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const primair = Display(
    id: 'primair',
    size: Size(1920, 1080),
    visiblePosition: Offset.zero,
    visibleSize: Size(1920, 1040),
  );
  const beamer = Display(
    id: 'beamer',
    size: Size(1280, 720),
    visiblePosition: Offset(1920, 0),
    visibleSize: Size(1280, 720),
  );

  late List<MethodCall> vensterOproepen;
  late ScreenRetrieverPlatform origineel;
  var vensterFaalt = false;

  const kanaal = MethodChannel('window_manager');

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    vensterOproepen = [];
    vensterFaalt = false;
    origineel = ScreenRetrieverPlatform.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanaal, (call) async {
          vensterOproepen.add(call);
          if (vensterFaalt) {
            throw PlatformException(code: 'boem', message: 'geen venster');
          }
          if (call.method == 'getBounds') {
            // Het venster staat op het primaire scherm.
            return <String, dynamic>{
              'x': 0.0,
              'y': 0.0,
              'width': 1200.0,
              'height': 800.0,
            };
          }
          return null;
        });
  });

  tearDown(() {
    ScreenRetrieverPlatform.instance = origineel;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanaal, null);
  });

  List<Slide> slides() => [
    Slide.create(SlideType.title).copyWith(title: 'Kwartaalcijfers'),
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Bevindingen', bullets: const ['Een', 'Twee']),
  ];

  /// Pompt de presentator met [displays] als schermen en wacht tot de lijst
  /// binnen is (dat gebeurt na het eerste frame, met echte async).
  Future<void> pumpPresenter(
    WidgetTester tester,
    List<Display> displays,
  ) async {
    final screens = _FakeScreens(displays);
    ScreenRetrieverPlatform.instance = screens;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: FullscreenPresenter(
          slides: slides(),
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (screens.gevraagd > 0 && vensterOproepen.isNotEmpty) break;
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // De wisselknop hoort bij het sprekersscherm (P); dat is ook de enige
    // plek waar hij zin heeft.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder wisselKnop() => find.byIcon(Icons.screen_share_outlined);

  testWidgets('met één scherm is er niets te wisselen', (tester) async {
    await pumpPresenter(tester, const [primair]);

    expect(
      wisselKnop(),
      findsNothing,
      reason: 'een knop die niets kan doen hoort er niet te staan',
    );

    // En de sneltoets doet dan ook niets met het venster.
    final voor = vensterOproepen.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(vensterOproepen.length, voor);
  });

  testWidgets('met twee schermen staat de wisselknop er', (tester) async {
    await pumpPresenter(tester, const [primair, beamer]);

    expect(wisselKnop(), findsOneWidget);
  });

  testWidgets('wisselen verhuist het venster naar het ándere scherm', (
    tester,
  ) async {
    await pumpPresenter(tester, const [primair, beamer]);
    vensterOproepen.clear();

    await tester.runAsync(() async {
      await tester.tap(wisselKnop());
      for (var i = 0; i < 40; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (vensterOproepen.any((c) => c.method == 'setBounds')) break;
      }
    });
    await tester.pump();

    final grenzen = vensterOproepen.firstWhere((c) => c.method == 'setBounds');
    final args = Map<String, dynamic>.from(grenzen.arguments as Map);
    expect(
      args['x'],
      1920.0,
      reason: 'het venster hoort naar het scherm te gaan waar het niet stond',
    );
    expect(args['width'], 1280.0);
    expect(args['height'], 720.0);

    // Volledig scherm gaat eerst uit en daarna weer aan: anders verhuist het
    // venster wél maar blijft het op de oude schermmaat staan.
    final volgorde = vensterOproepen
        .where((c) => c.method == 'setFullScreen' || c.method == 'setBounds')
        .map((c) => c.method)
        .toList();
    expect(volgorde, ['setFullScreen', 'setBounds', 'setFullScreen']);
  });

  testWidgets('lukt het wisselen niet, dan zegt de app dat', (tester) async {
    await pumpPresenter(tester, const [primair, beamer]);
    vensterFaalt = true;

    await tester.runAsync(() async {
      await tester.tap(wisselKnop());
      for (var i = 0; i < 40; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.text('Kon niet van scherm wisselen.').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    await tester.pump();

    expect(
      find.text('Kon niet van scherm wisselen.'),
      findsOneWidget,
      reason: 'stil falen laat de spreker naar het verkeerde scherm kijken',
    );

    // Laat de melding aflopen zodat de boom schoon wordt afgebroken.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
