import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, ThemeProfile profile) {
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

Color _hex(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

/// The image scrim is the only DecoratedBox carrying a LinearGradient built
/// from the title-background colour, so counting those identifies it.
int _titleScrimCount(WidgetTester tester, ThemeProfile profile) {
  final scrim = _hex(profile.titleBackgroundColor);
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) {
    final decoration = d.decoration;
    if (decoration is! BoxDecoration) return false;
    final gradient = decoration.gradient;
    return gradient is LinearGradient &&
        gradient.colors.any(
          (c) => (c.a > 0) && c.withValues(alpha: 1) == scrim,
        );
  }).length;
}

void main() {
  testWidgets('title slide can hide the image scrim', (tester) async {
    const profile = ThemeProfile(titleBackgroundColor: '#112233');
    final slide = Slide.create(SlideType.title).copyWith(
      title: 'Welkom',
      imagePath: 'missing.png',
      titleImageOverlay: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    expect(_titleScrimCount(tester, profile), 0);
  });

  testWidgets('title slide keeps the image scrim by default', (tester) async {
    const profile = ThemeProfile(titleBackgroundColor: '#112233');
    final slide = Slide.create(
      SlideType.title,
    ).copyWith(title: 'Welkom', imagePath: 'missing.png');

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    expect(_titleScrimCount(tester, profile), 1);
  });

  testWidgets('title slide without an image draws no scrim', (tester) async {
    const profile = ThemeProfile(titleBackgroundColor: '#112233');
    final slide = Slide.create(
      SlideType.title,
    ).copyWith(title: 'Welkom', subtitle: 'Ondertitel');

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    expect(_titleScrimCount(tester, profile), 0);
  });

  testWidgets(
    'a non-full-bleed title image uses the band layout (no overlay scrim)',
    (tester) async {
      const profile = ThemeProfile(titleBackgroundColor: '#112233');
      final slide = Slide.create(SlideType.title).copyWith(
        title: 'Welkom',
        imagePath: 'missing.png',
        imageSize: 60, // not full-bleed → image sits above the title band
        titleImageOverlay: true, // would add a scrim in full-bleed mode
      );

      await tester.pumpWidget(_host(slide, profile));
      await tester.pump();

      // The picture lives in its own zone, so no scrim is drawn behind the text
      // even though the overlay toggle is on.
      expect(_titleScrimCount(tester, profile), 0);
      expect(find.textContaining('Welkom'), findsOneWidget);
    },
  );
}
