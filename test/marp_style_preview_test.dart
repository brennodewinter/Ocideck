import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/marp_emoji.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  test('background url and emoji helpers stay local and predictable', () {
    expect(marpBackgroundAssetPath("url('images/bg.png')"), 'images/bg.png');
    expect(marpBackgroundAssetPath('linear-gradient(red, blue)'), isEmpty);
    expect(
      expandMarpEmojiShortcodes('Ga :rocket: maar laat :unknown: staan'),
      'Ga 🚀 maar laat :unknown: staan',
    );
  });

  testWidgets('deck and slide Marp colours, header and footer reach Flutter', (
    tester,
  ) async {
    const slide = Slide(
      id: 'colours',
      type: SlideType.bullets,
      title: 'Hallo :smile:',
      bullets: ['Tekst'],
      marpStyle: MarpStyle(backgroundColor: '#102030', footer: '*Voet*'),
    );
    final preview = SlidePreviewWidget(
      slide: slide,
      deckMarpStyle: const MarpStyle(color: 'red', header: '**Kop**'),
    );

    expect(preview.themeProfile.textColor, '#ff0000');
    expect(preview.themeProfile.slideBackgroundColor, '#102030');
    expect(preview.themeProfile.footerText, '*Voet*');

    await tester.pumpWidget(
      MaterialApp(home: SizedBox(width: 1280, height: 720, child: preview)),
    );
    expect(find.textContaining('😄', findRichText: true), findsOneWidget);
    expect(find.textContaining('Kop', findRichText: true), findsOneWidget);
    expect(find.textContaining('Voet', findRichText: true), findsOneWidget);
  });

  test('Flutter rejects the same unsupported CSS colour form as HTML', () {
    final preview = SlidePreviewWidget(
      slide: const Slide(
        id: 'css-colour',
        type: SlideType.bullets,
        title: 'Kleur',
        marpStyle: MarpStyle(color: 'rgb(1, 2, 3)'),
      ),
    );

    expect(preview.themeProfile.textColor, isNot('rgb(1, 2, 3)'));
  });

  testWidgets('fit and every scoped image filter use the shared renderer', (
    tester,
  ) async {
    const slide = Slide(
      id: 'filters',
      type: SlideType.section,
      title: 'Groot',
      imagePath: 'asset:assets/images/librekat-logo.png',
      marpStyle: MarpStyle(
        headingFit: true,
        imageFit: 'contain',
        imageFilters: ['blur:2', 'brightness:1.1', 'grayscale'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: SlidePreviewWidget(slide: slide),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FittedBox && widget.fit == BoxFit.contain,
      ),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.fit == BoxFit.contain,
      ),
      findsOneWidget,
    );
  });

  testWidgets('Flutter renders at most 32 filters without changing source', (
    tester,
  ) async {
    final filters = List<String>.filled(40, 'brightness:1.1');
    final slide = Slide(
      id: 'bounded-filters',
      type: SlideType.section,
      title: 'Begrensd',
      imagePath: 'asset:assets/images/librekat-logo.png',
      marpStyle: MarpStyle(imageFilters: filters),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: SlidePreviewWidget(slide: slide),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsNWidgets(32));
    expect(slide.marpStyle.imageFilters, hasLength(40));
  });
}
