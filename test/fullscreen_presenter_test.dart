import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
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
    expect(find.text('1 / 2'), findsNothing); // no audience chrome
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.byIcon(Icons.co_present_outlined), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('NOTITIES'), findsNothing); // presenter-only
    expect(find.text('VOLGENDE'), findsNothing);

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
}
