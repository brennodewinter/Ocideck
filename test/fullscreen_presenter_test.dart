import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Widget _host(List<Slide> slides) {
  return MaterialApp(
    home: FullscreenPresenter(
      slides: slides,
      projectPath: null,
      themeProfile: const ThemeProfile(),
      initialIndex: 0,
    ),
  );
}

void main() {
  final slides = [
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Eerste', bullets: ['a'], notes: 'Mijn spiekbriefje'),
    Slide.create(SlideType.bullets).copyWith(title: 'Tweede', bullets: ['b']),
  ];

  testWidgets('starts in audience view without presenter chrome', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget); // slide counter
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
    expect(find.text('1 / 2'), findsOneWidget);

    // Blank to black: the slide (and its counter) disappears.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('1 / 2'), findsNothing);

    // Same key restores the slide.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blanked screen resumes on the next navigation press', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('1 / 2'), findsNothing);

    // First arrow un-blanks without advancing (still on slide 1).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

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
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('End jumps to the last slide and Home back to the first', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

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
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing a number and Enter jumps to that slide', (tester) async {
    final three = [
      ...slides,
      Slide.create(SlideType.bullets).copyWith(title: 'Derde', bullets: ['c']),
    ];
    await tester.pumpWidget(_host(three));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);

    // Type "3" → a badge appears, Enter jumps to slide 3.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget); // badge "<typed> / <total>"

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Badge gone, now actually on slide 3 (counter shows it).
    expect(find.text('3 / 3'), findsOneWidget); // slide counter now
    expect(find.byIcon(Icons.south_east), findsNothing); // badge icon gone

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('? toggles the shortcut cheatsheet', (tester) async {
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Sneltoetsen'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(find.text('Sneltoetsen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Sneltoetsen'), findsNothing);
    // Esc closed the help, not the presentation.
    expect(find.text('1 / 2'), findsOneWidget);

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
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
