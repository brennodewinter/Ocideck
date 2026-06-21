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

int _titleOverlayCount(WidgetTester tester, ThemeProfile profile) {
  final overlay = _hex(profile.titleBackgroundColor).withValues(alpha: 0.62);
  return tester.widgetList<Container>(find.byType(Container)).where((c) {
    return c.color == overlay;
  }).length;
}

void main() {
  testWidgets('title slide can hide the image overlay haze', (tester) async {
    const profile = ThemeProfile(titleBackgroundColor: '#112233');
    final slide = Slide.create(SlideType.title).copyWith(
      title: 'Welkom',
      imagePath: 'missing.png',
      titleImageOverlay: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    expect(_titleOverlayCount(tester, profile), 0);
  });

  testWidgets('title slide keeps the image overlay haze by default', (
    tester,
  ) async {
    const profile = ThemeProfile(titleBackgroundColor: '#112233');
    final slide = Slide.create(
      SlideType.title,
    ).copyWith(title: 'Welkom', imagePath: 'missing.png');

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    expect(_titleOverlayCount(tester, profile), 1);
  });
}
