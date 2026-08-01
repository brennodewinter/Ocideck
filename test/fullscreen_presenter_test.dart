import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/split_run.dart';
import 'package:ocideck/widgets/presentation/annotation_overlay.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Widget _host(
  List<Slide> slides, {
  Map<String, String> initialUserNotes = const {},
  void Function(Map<String, String>)? onUserNotesChanged,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    home: FullscreenPresenter(
      slides: slides,
      projectPath: null,
      themeProfile: const ThemeProfile(),
      initialIndex: 0,
      initialUserNotes: initialUserNotes,
      onUserNotesChanged: onUserNotesChanged,
    ),
  );
}

/// The presenter pushed over a launcher screen, so its exit (a `Navigator.pop`)
/// is observable: "open" being back on screen means the presentation closed.
Widget _presenterOverLauncher({bool showRehearsalSummary = false}) =>
    MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FullscreenPresenter(
                  slides: [
                    Slide.create(
                      SlideType.bullets,
                    ).copyWith(title: 'Eerste', bullets: ['a']),
                    Slide.create(
                      SlideType.bullets,
                    ).copyWith(title: 'Tweede', bullets: ['b']),
                  ],
                  projectPath: null,
                  themeProfile: const ThemeProfile(),
                  initialIndex: 0,
                  showRehearsalSummary: showRehearsalSummary,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> sendControlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  final slides = [
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Eerste', bullets: ['a'], notes: 'Mijn spiekbriefje'),
    Slide.create(SlideType.bullets).copyWith(title: 'Tweede', bullets: ['b']),
  ];

  test('dual-screen mode is available on every desktop platform', () {
    expect(shouldUseDualScreen(isDesktopNative: true, displayCount: 2), isTrue);
  });

  test('dual-screen mode is unavailable on web', () {
    expect(
      shouldUseDualScreen(isDesktopNative: false, displayCount: 2),
      isFalse,
    );
  });

  test('AudienceWindowHandle closes only once', () async {
    var closeCount = 0;
    final handle = AudienceWindowHandle(
      WindowController.fromWindowId('test'),
      closeImpl: (_) async {
        closeCount++;
      },
    );

    await handle.close();
    await handle.close();

    expect(closeCount, 1);
    expect(handle.isClosed, isTrue);
  });

  testWidgets('a key forwarded from the beamer window drives the presenter', (
    tester,
  ) async {
    // Het beamervenster stuurt toetsen die het zelf niet afhandelt hierheen.
    // Zonder die brug is de presentatie onbestuurbaar zodra dat venster de
    // toetsenbordfocus heeft — dan doet Escape niets en zit je muurvast.
    // Dual-schermmodus toont de presenter view; die heeft laptopformaat nodig.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      bridge,
      (call) async => null,
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
    // De handler registreert zich asynchroon over dezelfde brug.
    await tester.pumpAndSettle();

    Future<void> forward(LogicalKeyboardKey key) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          bridge.name,
          bridge.codec.encodeMethodCall(
            MethodCall('methodCall', {
              'channel': 'ocideck/presenter',
              'method': 'key',
              'arguments': {
                'keyId': key.keyId,
                'meta': false,
                'control': false,
                'shift': false,
              },
            }),
          ),
          (_) {},
        );

    await forward(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // En de weg terug: Escape sluit het raster, precies wat op het
    // beamervenster vroeger niet aankwam.
    await forward(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Slide-overzicht'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  test('dual-screen mode requires a desktop platform and two displays', () {
    expect(
      shouldUseDualScreen(isDesktopNative: true, displayCount: 1),
      isFalse,
    );
    expect(
      shouldUseDualScreen(isDesktopNative: false, displayCount: 2),
      isFalse,
    );
  });

  test('autoplay audio or video takes precedence over slide timing', () {
    expect(
      autoAdvanceWaitsForMedia(
        Slide.create(SlideType.bullets).copyWith(
          advanceDuration: 3,
          audioPath: 'sound.mp3',
          audioAutoplay: true,
        ),
      ),
      isTrue,
    );
    expect(
      autoAdvanceWaitsForMedia(
        Slide.create(SlideType.video).copyWith(
          advanceDuration: 3,
          videoPath: 'movie.mp4',
          videoAutoplay: true,
        ),
      ),
      isTrue,
    );
    expect(
      autoAdvanceWaitsForMedia(
        Slide.create(SlideType.video).copyWith(
          advanceDuration: 3,
          videoPath: 'movie.mp4',
          videoAutoplay: false,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('slide timer does not interrupt autoplay media', (tester) async {
    final mediaSlides = [
      Slide.create(SlideType.video).copyWith(
        title: 'Video blijft staan',
        videoPath: '/tmp/does-not-exist.mp4',
        videoAutoplay: true,
        advanceDuration: 3,
      ),
      Slide.create(SlideType.bullets).copyWith(title: 'Na video'),
    ];

    await tester.pumpWidget(_host(mediaSlides));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Video blijft staan'), findsOneWidget);
    expect(find.text('Na video'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('de zoom-toetsen bladeren niet en breken de navigatie niet (#930)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Eerste dia', bullets: ['x']),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Tweede dia', bullets: ['y']),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Eerste dia'), findsOneWidget);

    // '-' en '=/+' zijn zoom-toetsen voor een groot diagram (#930). Staat er geen
    // zoombaar diagram op de dia, dan doen ze niets — en ze mogen zéker niet
    // vooruit/terug bladeren.
    for (final key in const [
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.numpadAdd,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(find.text('Eerste dia'), findsOneWidget);
    expect(find.text('Tweede dia'), findsNothing);

    // Pijl-rechts bladert nog wél: de nieuwe toetsen hebben de afhandeling niet
    // gebroken.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Tweede dia'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('checklist changes during presenting are persisted', (
    tester,
  ) async {
    Slide? updated;
    final checklistSlides = [
      Slide.create(SlideType.bullets).copyWith(
        title: 'Taken',
        bullets: ['[ ] Live afvinken'],
        listStyle: ListStyle.checklist,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: checklistSlides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
          onSlideChanged: (slide) => updated = slide,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('checklist-preview-toggle-0-0')),
    );
    await tester.pump();

    expect(updated?.bullets, ['[x] Live afvinken']);
    expect(find.text('☑ '), findsOneWidget);
  });

  testWidgets(
    'table edit mode enters with E, persists changes, exits with Esc',
    (tester) async {
      Slide? updated;
      final tableSlides = [
        Slide.create(SlideType.table).copyWith(
          title: 'Cijfers',
          tableEditable: true,
          tableRows: [
            ['Kolom', 'Waarde'],
            ['Omzet', '100'],
          ],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenPresenter(
            slides: tableSlides,
            projectPath: null,
            themeProfile: const ThemeProfile(),
            initialIndex: 0,
            onSlideChanged: (slide) => updated = slide,
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(find.text('Tabel bewerken'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('table-edit-cell-1-1')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('table-edit-cell-1-1')),
        '250',
      );
      await tester.pump();

      expect(updated?.tableRows[1][1], '250');

      // Terwijl een cel in bewerking is mag 'e' geen sneltoets zijn: het typt in
      // de cel en sluit de bewerking niet af.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(find.text('Tabel bewerken'), findsOneWidget);

      // Afsluiten doe je met Esc.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Tabel bewerken'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('F lost een te volle dia live op door te splitsen (#914)', (
    tester,
  ) async {
    String? splitId;
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Te vol',
      bullets: [for (var i = 0; i < 20; i++) 'Punt ${i + 1}'],
    );
    // Groeibare lijst: de presenter voegt de vervolgpagina's er in-place bij.
    final slides = <Slide>[slide];
    const profile = ThemeProfile();
    final before = splitRunLayoutIndex(slides, profile, profile.fontFamily);
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: slides,
          projectPath: null,
          themeProfile: profile,
          initialIndex: 0,
          onSlideSplit: (id) => splitId = id,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    // De knip is op de bron doorgeschreven (via het id) en de dia is lokaal al
    // in pagina's gevallen — met alle bullets nog aanwezig.
    expect(splitId, slide.id);
    expect(slides.length, greaterThan(1));
    expect(slides.fold<int>(0, (sum, s) => sum + s.bullets.length), 20);
    expect(
      splitRunLayoutIndex(slides, profile, profile.fontFamily),
      isNot(same(before)),
      reason: 'de in-place live-fix moet de geprimeerde layoutindex vergeten',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'F op een prima dia meldt dat er niets op te lossen valt (#914)',
    (tester) async {
      String? splitId;
      final slides = <Slide>[
        Slide.create(SlideType.bullets).copyWith(bullets: ['Kort', 'Bondig']),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenPresenter(
            slides: slides,
            projectPath: null,
            themeProfile: const ThemeProfile(),
            initialIndex: 0,
            onSlideSplit: (id) => splitId = id,
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(splitId, isNull);
      expect(slides.length, 1);
      expect(find.text('Geen probleem om hier op te lossen.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pencil toggle on a table slide turns edit mode on and off', (
    tester,
  ) async {
    final tableSlides = [
      Slide.create(SlideType.table).copyWith(
        title: 'Cijfers',
        tableEditable: true,
        tableRows: [
          ['Kolom', 'Waarde'],
          ['Omzet', '100'],
        ],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: tableSlides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    // Op een tabeldia is het potlood-icoon zichtbaar, maar bewerken staat uit.
    final toggle = find.byTooltip('Tabel bewerken (E)');
    expect(toggle, findsOneWidget);
    expect(find.text('Tabel bewerken'), findsNothing);

    // Klikken schakelt bewerken aan (net als de E-toets).
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsOneWidget);

    // Nogmaals klikken sluit het weer.
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keys during table edit never navigate or exit', (tester) async {
    // Twee dia's: een tabeldia en een gewone dia erna. Navigeren reset de
    // tabelbewerking, dus zolang "Tabel bewerken" zichtbaar blijft is er noch
    // doorgebladerd noch uit de bewerking gesprongen.
    final tableSlides = [
      Slide.create(SlideType.table).copyWith(
        title: 'Cijfers',
        tableEditable: true,
        tableRows: [
          ['Kolom', 'Waarde'],
          ['Omzet', '100'],
        ],
      ),
      Slide.create(SlideType.bullets).copyWith(title: 'Tweede'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: tableSlides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsOneWidget);

    // Letters (incl. 'e'), spatie en cijfers horen tijdens het bewerken naar de
    // cel te gaan: geen sneltoetsrol, dus geen doorbladeren of afsluiten. De
    // pijltjes sturen de tekstcursor in de cel en mogen evenmin navigeren.
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    expect(
      find.text('Tabel bewerken'),
      findsOneWidget,
      reason: 'noch doorbladeren noch uit de bewerking springen',
    );

    // Esc blijft de enige uitgang.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a read-only table offers no edit toggle and E acts as eraser', (
    tester,
  ) async {
    // Standaard staat een tabel op alleen-lezen (tableEditable == false): geen
    // potlood-icoon, en E valt terug op het gum-gereedschap.
    final tableSlides = [
      Slide.create(SlideType.table).copyWith(
        title: 'Cijfers',
        tableRows: [
          ['Kolom', 'Waarde'],
          ['Omzet', '100'],
        ],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: tableSlides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Tabel bewerken (E)'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsNothing);
    expect(find.byIcon(Icons.cleaning_services_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('E still selects eraser on non-table slides', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.text('Tabel bewerken'), findsNothing);
    expect(find.byIcon(Icons.cleaning_services_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starts in audience view without presenter chrome', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    expect(find.text('Eerste'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.byIcon(Icons.co_present_outlined), findsNothing);
    expect(find.text('NOTITIES'), findsNothing); // presenter-only
    expect(find.text('VOLGENDE'), findsNothing);

    // De bedieningsbalk zit sinds #607 wél in de boom, maar volledig
    // doorzichtig tot je de muis beweegt. Deze test zei eerder "geen
    // sluitknop"; dat is niet meer waar en het is ook niet meer wat hij hoort
    // te bewaken — wat telt is dat er niets te zíen is.
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );

    await tester.pumpWidget(const SizedBox()); // dispose → cancel clock timer
  });

  testWidgets('P toggles presenter view with notes and next slide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();

    expect(find.text('NOTITIES'), findsOneWidget);
    expect(find.text('Mijn spiekbriefje'), findsOneWidget);
    expect(find.text('VOLGENDE'), findsOneWidget);
    expect(find.text('Slide 1 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('advancing updates the notes shown in presenter view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Mijn spiekbriefje'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    // Slide 2 has no notes → placeholder, and we're on its end-of-deck next.
    expect(find.text('Geen notities voor deze slide.'), findsOneWidget);
    expect(find.text('Einde van de presentatie'), findsOneWidget);
    expect(find.text('Slide 2 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('B blanks the audience screen and toggles back', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    // Blank to black: the slide disappears.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('Eerste'), findsNothing);

    // Same key restores the slide.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blanked screen resumes on the next navigation press', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('Eerste'), findsNothing);

    // First arrow un-blanks without advancing (still on slide 1).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('G opens the grid and tapping a tile jumps to that slide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // Tap the tile for slide 2.
    await tester.tap(find.text('2'));
    await tester.pump();

    // Grid closed and we jumped to slide 2.
    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Tweede'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('End jumps to the last slide and Home back to the first', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('grid arrow keys move a cursor and Enter jumps to it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // Move the cursor to slide 2 with the arrow key, then choose it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Tweede'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing a number and Enter jumps to that slide', (tester) async {
    final three = [
      ...slides,
      Slide.create(SlideType.bullets).copyWith(title: 'Derde', bullets: ['c']),
    ];
    await tester.pumpWidget(_host(three));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    // Type "3" → a badge appears, Enter jumps to slide 3.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget); // badge "<typed> / <total>"

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Badge gone, now actually on slide 3.
    expect(find.text('Derde'), findsOneWidget);
    expect(find.text('3 / 3'), findsNothing);
    expect(find.byIcon(Icons.south_east), findsNothing); // badge icon gone

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('? toggles the shortcut cheatsheet', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Toetsenlegenda'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(find.text('Toetsenlegenda'), findsOneWidget);
    expect(find.text('Scherm wisselen (meerdere schermen)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Toetsenlegenda'), findsNothing);
    // Esc closed the help, not the presentation.
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape closes the grid before it would exit', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // Esc closes the grid and leaves us in the presentation (no exit).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape closes the presentation when nothing is open', (
    tester,
  ) async {
    // The layered Escape (help, grid, user notes, table, tool, typed number,
    // blank) was covered layer by layer, but never the bottom of the stack:
    // nothing open, so Escape leaves the presentation. That gap is why a report
    // of "Escape does not exit" could not be checked against a test.
    const windowManager = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowManager,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManager,
        null,
      ),
    );

    await tester.pumpWidget(_presenterOverLauncher());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Eerste'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('with the rehearsal summary on, Escape shows it before leaving', (
    tester,
  ) async {
    // The summary is on by default, so this — not a straight exit — is what
    // most authors meet when they press Escape: the run appears, and closing it
    // ends the presentation. Worth pinning down, because "Escape did nothing"
    // is exactly how a summary that failed to appear would look.
    const windowManager = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowManager,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManager,
        null,
      ),
    );

    await tester.pumpWidget(_presenterOverLauncher(showRehearsalSummary: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Still presenting, with the run on top of it.
    expect(find.text('Oefenrun'), findsOneWidget);
    expect(find.text('open'), findsNothing);

    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Ctrl/Cmd + W closes the presentation', (tester) async {
    // Exit takes the single-screen path, which drops full screen via the
    // window_manager plugin; stub it so the platform call resolves in the test.
    const windowManager = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowManager,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManager,
        null,
      ),
    );

    // Push the presenter over a launcher screen so its exit (Navigator.pop)
    // is observable; disable the rehearsal summary so exit goes straight through.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullscreenPresenter(
                    slides: slides,
                    projectPath: null,
                    themeProfile: const ThemeProfile(),
                    initialIndex: 0,
                    showRehearsalSummary: false,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Eerste'), findsOneWidget);

    await sendControlKey(tester, LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();

    // Back on the launcher: the presentation closed.
    expect(find.text('Eerste'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('user notes panel is hidden by default', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Mijn notities'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl+N toggles user notes panel', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsOneWidget);

    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a plain N opens the user notes panel', (tester) async {
    // De legenda belooft "N": zonder modifier deed die toets vroeger niets,
    // waardoor de sneltoets in de praktijk onvindbaar was.
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsOneWidget);

    // Binnen het notitieveld typt een kale N een letter, dus daar sluit alleen
    // Ctrl+N (of Esc) het paneel weer.
    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape closes user notes without exiting presentation', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Mijn notities'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an in-progress stroke commits to the old slide on navigation', (
    tester,
  ) async {
    Map<String, List<InkStroke>>? captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: FullscreenPresenter(
          slides: slides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
          onAnnotationsChanged: (ink) => captured = ink,
        ),
      ),
    );
    await tester.pump();

    // Pen aan en een streek beginnen zonder de muisknop los te laten.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    final center = tester.getCenter(find.byType(AnnotationLayer).first);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 20));
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();

    // Navigeren terwijl de streek nog bezig is: de streek hoort op de
    // oude slide te belanden in plaats van te verdwijnen.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(captured, isNotNull);
    final strokes = captured![annotationKey(slides.first.id, 0)];
    expect(strokes, isNotNull);
    expect(strokes, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PgUp/PgDn navigates slides while user notes stay open', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(find.text('Mijn notities'), findsOneWidget);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);
    expect(find.text('Mijn notities'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);
    expect(find.text('Mijn notities'), findsOneWidget);

    // Pijltjestoetsen blijven bij het tekstveld: geen slidewissel.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing in user notes does not change speaker notes', (
    tester,
  ) async {
    Map<String, String>? captured;
    await tester.pumpWidget(
      _host(slides, onUserNotesChanged: (notes) => captured = notes),
    );
    await tester.pump();

    await sendControlKey(tester, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();

    final userField = find.descendant(
      of: find.byKey(const ValueKey('presenter-user-notes')),
      matching: find.byType(TextField),
    );
    await tester.enterText(userField, 'Cursusvraag');
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.values, contains('Cursusvraag'));
    expect(slides.first.notes, 'Mijn spiekbriefje');

    await tester.pumpWidget(const SizedBox());
  });

  // #607: de publieksweergave had géén bediening — geen dianummer, geen
  // pijlen, geen sluitknop, en nergens stond dat Esc werkt. Wie voor het eerst
  // presenteert moest raden hoe hij eruit kwam, voor een zaal.
  group('bedieningsbalk in publieksweergave', () {
    List<Slide> tweeDias() => [
      Slide.create(SlideType.bullets).copyWith(title: 'Een', bullets: ['a']),
      Slide.create(SlideType.bullets).copyWith(title: 'Twee', bullets: ['b']),
    ];

    testWidgets('staat er niet zolang de muis stilstaat', (tester) async {
      await tester.pumpWidget(_host(tweeDias()));
      await tester.pump();

      // Aanwezig maar volledig doorzichtig: een projectiebeeld hoort geen
      // permanente knoppen te dragen — die staan straks op de foto van de zaal.
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('verschijnt bij muisbeweging en verdwijnt weer', (
      tester,
    ) async {
      await tester.pumpWidget(_host(tweeDias()));
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(FullscreenPresenter))),
      );
      await tester.pump();

      expect(
        find.byIcon(Icons.close),
        findsWidgets,
        reason: 'hoe kom ik eruit',
      );
      final zichtbaar = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(zichtbaar.opacity, 1);

      // En weer weg, zodat de balk niet de rest van de presentatie blijft staan.
      await tester.pump(const Duration(seconds: 4));
      final verborgen = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(verborgen.opacity, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('toont geen slidenummer op het projectiebeeld (#864)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(tweeDias()));
      await tester.pump();

      // Balk volledig zichtbaar maken; zelfs dán hoort er geen "1 / 2" op de
      // zaal te staan. Het nummer leidt af en belandt op iedere foto — het
      // blijft in de presenter-cockpit, niet op het projectiebeeld.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(FullscreenPresenter))),
      );
      await tester.pump();

      expect(find.textContaining(RegExp(r'\d\s*/\s*\d')), findsNothing);
      // De knoppen om verder te komen en eruit te stappen blijven wél (#607).
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.close), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('de pijl brengt je naar de volgende dia', (tester) async {
      await tester.pumpWidget(_host(tweeDias()));
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(FullscreenPresenter))),
      );
      await tester.pump();

      expect(find.text('Een'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      // Zonder teller bewijst de dia-inhoud zelf de sprong naar de volgende dia.
      expect(find.text('Twee'), findsOneWidget);
      expect(find.text('Een'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('online-media-knop in presentatie (#865)', () {
    /// Dual-screen mode vereist een AudienceWindowHandle; we gebruiken de
    /// test-window-controller die ook de rest van deze suite gebruikt.
    Widget dualHost(List<Slide> slides, {bool allowRemoteMedia = false}) {
      return MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: FullscreenPresenter(
          slides: slides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
          allowRemoteMedia: allowRemoteMedia,
          audience: AudienceWindowHandle(
            WindowController.fromWindowId('test'),
            closeImpl: (_) async {},
          ),
        ),
      );
    }

    testWidgets(
      'dual-screen: toont hint bij remote afbeelding en allowRemoteMedia uit',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final slides = [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'https://example.com/photo.jpg'),
        ];

        await tester.pumpWidget(dualHost(slides));
        await tester.pumpAndSettle();

        expect(find.textContaining('Online media staat uit'), findsWidgets);
      },
    );

    testWidgets(
      'dual-screen: toont geen hint wanneer allowRemoteMedia aan staat',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final slides = [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'https://example.com/photo.jpg'),
        ];

        await tester.pumpWidget(dualHost(slides, allowRemoteMedia: true));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Online media staat uit — aanzetten'),
          findsNothing,
        );
      },
    );

    testWidgets('dual-screen: toont geen hint bij lokale afbeelding', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final slides = [
        Slide.create(SlideType.image).copyWith(imagePath: 'media/local.jpg'),
      ];

      await tester.pumpWidget(dualHost(slides));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Online media staat uit — aanzetten'),
        findsNothing,
      );
    });
  });
}
