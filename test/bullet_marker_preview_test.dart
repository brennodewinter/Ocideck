import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, {ThemeProfile profile = const ThemeProfile()}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(slide: slide, themeProfile: profile),
        ),
      ),
    ),
  );
}

int _pawCount(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((c) => c.painter?.runtimeType.toString() == '_PawPainter')
    .length;

void main() {
  final slide = Slide.create(
    SlideType.bullets,
  ).copyWith(title: 'Punten', bullets: const ['Een', 'Twee']);

  testWidgets('a numbered list continues from numberStart across slides', (
    tester,
  ) async {
    final second = Slide.create(SlideType.bullets).copyWith(
      title: 'Vervolg',
      bullets: const ['Vier', 'Vijf'],
      listStyle: ListStyle.numbered,
      continueNumbering: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 450,
              // As if the previous slide ended at 3.
              child: SlidePreviewWidget(slide: second, numberStart: 4),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('4. '), findsOneWidget);
    expect(find.text('5. '), findsOneWidget);
    expect(find.text('1. '), findsNothing);
  });

  testWidgets('bullets show the dot marker by default (no paws)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(find.text('• '), findsWidgets);
    expect(_pawCount(tester), 0);
  });

  testWidgets('a per-slide paw override swaps the dot for a drawn paw', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(slide.copyWith(bulletMarkerOverride: BulletMarker.paw)),
    );
    await tester.pump();

    expect(find.text('• '), findsNothing);
    expect(_pawCount(tester), 2); // one per bullet
  });

  testWidgets('the theme default applies paws to every bullet', (tester) async {
    await tester.pumpWidget(
      _host(slide, profile: const ThemeProfile(bulletMarker: BulletMarker.paw)),
    );
    await tester.pump();

    expect(_pawCount(tester), 2);
  });

  testWidgets('a per-slide dot override beats a paw theme default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        slide.copyWith(bulletMarkerOverride: BulletMarker.dot),
        profile: const ThemeProfile(bulletMarker: BulletMarker.paw),
      ),
    );
    await tester.pump();

    expect(find.text('• '), findsWidgets);
    expect(_pawCount(tester), 0);
  });
}
