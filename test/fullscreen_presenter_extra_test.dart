import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

Widget _host(List<Slide> slides, {int initialIndex = 0}) {
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: FullscreenPresenter(
      slides: slides,
      projectPath: null,
      themeProfile: const ThemeProfile(),
      initialIndex: initialIndex,
    ),
  );
}

void main() {
  final List<Slide> slides = <Slide>[
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Eerste', bullets: <String>['a'], notes: 'Spiek'),
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Tweede', bullets: <String>['b']),
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Derde', bullets: <String>['c']),
  ];

  setUp(() {
    // The presenter has its own timers/animations, so we never settle; this
    // keeps each test on a comfortably large surface to avoid overflow.
  });

  void sizeUp(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('space and PageDown advance, PageUp and arrowLeft go back', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.text('Derde'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('next does not wrap past the last slide without loop', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides, initialIndex: 2));
    await tester.pump();
    expect(find.text('Derde'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // Stays on the last slide (no wrap to the first).
    expect(find.text('Derde'), findsOneWidget);
    expect(find.text('Eerste'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prev stays put on the first slide', (WidgetTester tester) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('W blanks the audience screen to white and toggles back', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(find.text('Eerste'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('K opens the target-time input and Enter commits it away', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.textContaining('Doeltijd'), findsOneWidget);

    // Type a target (20:00) — digits feed the MMSS field, not slide jumps.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pump();
    expect(find.text('20:00'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Badge gone, still presenting the same slide.
    expect(find.textContaining('Doeltijd'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape cancels the target-time input without exiting', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.textContaining('Doeltijd'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.textContaining('Doeltijd'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A, L and M toggles keep presenting without crashing', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyM,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    // The slide is still shown and navigation still works after the toggles.
    expect(find.text('Eerste'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('R resets the rehearsal timer without leaving the slide', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backspace edits the typed slide number before Enter', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    // Type "13", backspace to "1", then commit → first slide.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(find.text('13 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('1 / 3'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape first clears a typed number, then later blanks/exit', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Esc clears the typed badge but stays in the presentation.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('2 / 3'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('grid Down/Up/Home/End move the cursor and Space jumps', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // End moves the cursor to the last tile; Space jumps to it.
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Derde'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('grid Home moves the cursor back to the first slide', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides, initialIndex: 2));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('grid arrowDown then arrowUp returns to the start tile', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    // Down then Up cancels out (3 columns by default), so Enter stays on 1.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('G inside the grid closes it again', (WidgetTester tester) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.text('Slide-overzicht'), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('D selects the pen and shows the annotation toolbar', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(find.byIcon(Icons.edit), findsWidgets);
    expect(find.byIcon(Icons.my_location), findsOneWidget); // laser button

    // Escape drops the tool but keeps the presentation open.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byIcon(Icons.my_location), findsNothing);
    expect(find.text('Eerste'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('T selects the highlighter tool', (WidgetTester tester) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(find.byIcon(Icons.brush), findsOneWidget);

    // Same key toggles it back off.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(find.byIcon(Icons.brush), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('X selects the laser tool', (WidgetTester tester) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('numpad digits and numpad Enter jump to a slide', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);
    expect(find.text('2 / 3'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blanked screen restores on Home rather than jumping', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    await tester.pumpWidget(_host(slides, initialIndex: 1));
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.text('Tweede'), findsNothing);

    // First Home press un-blanks without moving off slide 2.
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(find.text('Tweede'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('toggling auto-play off lets a timed slide stay put', (
    WidgetTester tester,
  ) async {
    sizeUp(tester);
    final List<Slide> timed = <Slide>[
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Snel', bullets: <String>['a'], advanceDuration: 1),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Daarna', bullets: <String>['b']),
    ];
    await tester.pumpWidget(_host(timed));
    await tester.pump();
    expect(find.text('Snel'), findsOneWidget);

    // Pause auto-play (A) so the slide timer is cancelled; pumping past the
    // 1s duration must NOT advance us off the first slide.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.text('Snel'), findsOneWidget);
    expect(find.text('Daarna'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
