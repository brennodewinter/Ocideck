import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/settings.dart';
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

  testWidgets(
    'deckfooter verplaatst een onderlogo alleen in de effectieve preview',
    (tester) async {
      const profile = ThemeProfile(
        logoPath: 'asset:assets/images/vigilis-logo.png',
        logoPosition: 'bottom-left',
      );
      final slide = Slide.create(SlideType.bullets);

      final withFooter = SlidePreviewWidget(
        slide: slide,
        themeProfile: profile,
        deckMarpStyle: const MarpStyle(footer: 'Vertrouwelijk'),
      );
      final withoutFooter = SlidePreviewWidget(
        slide: slide,
        themeProfile: profile,
      );

      expect(withFooter.themeProfile.logoPosition, 'top-left');
      expect(withoutFooter.themeProfile.logoPosition, 'bottom-left');
      expect(profile.logoPosition, 'bottom-left');

      Future<Positioned> renderedLogoPosition(
        SlidePreviewWidget preview,
      ) async {
        await tester.pumpWidget(
          MaterialApp(home: SizedBox(width: 1280, height: 720, child: preview)),
        );
        await tester.pumpAndSettle();
        final image = find.byType(Image);
        expect(image, findsOneWidget);
        return tester.widget<Positioned>(
          find.ancestor(of: image, matching: find.byType(Positioned)).first,
        );
      }

      final moved = await renderedLogoPosition(withFooter);
      expect(moved.top, isNotNull);
      expect(moved.bottom, isNull);

      final unchanged = await renderedLogoPosition(withoutFooter);
      expect(unchanged.top, isNull);
      expect(unchanged.bottom, isNotNull);
    },
  );

  testWidgets('background colour stays behind a transparent background image', (
    tester,
  ) async {
    final preview = SlidePreviewWidget(
      slide: const Slide(
        id: 'layered-background',
        type: SlideType.bullets,
        title: 'Lagen',
        marpStyle: MarpStyle(
          backgroundColor: '#fff3cf',
          backgroundImage: "url('assets/images/librekat-logo.png')",
        ),
      ),
    );

    expect(preview.themeProfile.slideBackgroundColor, '#fff3cf');
    await tester.pumpWidget(
      MaterialApp(home: SizedBox(width: 1280, height: 720, child: preview)),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xfffff3cf),
      ),
      findsWidgets,
    );
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
