import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, ThemeProfile profile) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(slide: slide, themeProfile: profile),
      ),
    ),
  );
}

Color _hex(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

TextStyle? _styleForText(WidgetTester tester, String text) {
  TextStyle? findInSpan(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text == text) return span.style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        final found = findInSpan(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = findInSpan(richText.text);
    if (found != null) return found;
  }
  return null;
}

void main() {
  testWidgets('code slide paints the themed background colour', (tester) async {
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(codeLanguage: 'dart', customMarkdown: 'void main() {}');
    const profile = ThemeProfile(
      codeBackgroundColor: '#000000',
      codeTextColor: '#33FF33',
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    // The code panel uses the themed background somewhere in its decoration.
    final painted = tester.widgetList<Container>(find.byType(Container)).where((
      c,
    ) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == _hex('#000000');
    });
    expect(painted, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'syntax highlighting on uses highlighted code for a known language',
    (tester) async {
      final slide = Slide.create(
        SlideType.code,
      ).copyWith(codeLanguage: 'dart', customMarkdown: 'void main() {}');
      const profile = ThemeProfile(codeHighlightSyntax: true);

      await tester.pumpWidget(_host(slide, profile));
      await tester.pump();

      expect(find.byKey(const Key('highlighted_code')), findsOneWidget);
    },
  );

  testWidgets('syntax highlighting off renders monochrome (CRT) text', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(codeLanguage: 'dart', customMarkdown: 'void main() {}');
    const profile = ThemeProfile(
      codeBackgroundColor: '#000000',
      codeTextColor: '#33FF33',
      codeHighlightSyntax: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    // No per-token highlighting; the code is one flat colour.
    expect(find.byKey(const Key('highlighted_code')), findsNothing);
    final codeText = tester.widget<Text>(find.text('void main() {}'));
    expect(codeText.style?.color, _hex('#33FF33'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short code is enlarged to use the space; long code shrinks', (
    tester,
  ) async {
    const profile = ThemeProfile(codeHighlightSyntax: false);

    const short = 'x';
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.code).copyWith(customMarkdown: short),
        profile,
      ),
    );
    await tester.pump();
    final shortSize = tester.widget<Text>(find.text(short)).style!.fontSize!;

    final long = List.generate(
      40,
      (i) => 'final someRatherLongVariableName$i = compute($i);',
    ).join('\n');
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.code).copyWith(customMarkdown: long),
        profile,
      ),
    );
    await tester.pump();
    final longSize = tester.widget<Text>(find.text(long)).style!.fontSize!;

    // A tiny snippet is scaled up to fill; a big one is scaled down to fit.
    expect(longSize, lessThan(shortSize));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the slide title sits above the code panel, not inside it', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(title: 'Voorbeeld', customMarkdown: 'print("hi")');
    const profile = ThemeProfile(
      titleTextColor: '#FFFFFF',
      titleBackgroundColor: '#1C2B47',
      codeBackgroundColor: '#000000',
      codeTextColor: '#33FF33',
      codeHighlightSyntax: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    // The title is rendered above the code panel rather than inside it.
    final titleBottom = tester.getBottomLeft(find.text('Voorbeeld')).dy;
    final codeTop = tester.getTopLeft(find.text('print("hi")')).dy;
    expect(titleBottom, lessThanOrEqualTo(codeTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('code slide title uses the regular slide title style', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(title: 'Voorbeeld', customMarkdown: 'print("hi")');
    const profile = ThemeProfile(
      textColor: '#123456',
      titleTextColor: '#FFFFFF',
      titleBackgroundColor: '#FF00FF',
      codeHighlightSyntax: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    final titleStyle = _styleForText(tester, 'Voorbeeld');
    expect(titleStyle?.color, _hex('#123456'));
    expect(titleStyle?.fontSize, closeTo(800 * 0.042, 0.001));

    final titleCards = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.color == _hex('#FF00FF');
        });
    expect(titleCards, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'code panel extends to full height — logo sits in the corner (#1932)',
    (tester) async {
      final slide = Slide.create(SlideType.code).copyWith(
        title: 'Voorbeeld',
        customMarkdown: 'print("hi")',
        showLogo: true,
      );
      const profile = ThemeProfile(
        logoPath: 'logo.png',
        logoPosition: 'bottom-right',
        logoSize: 128,
        codeHighlightSyntax: false,
      );

      await tester.pumpWidget(_host(slide, profile));
      await tester.pump();

      final codePanel = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.color == _hex(profile.codeBackgroundColor);
          })
          .single;
      final panelBottom = tester.getBottomLeft(find.byWidget(codePanel)).dy;
      final slideBottom = tester
          .getBottomLeft(find.byType(SlidePreviewWidget))
          .dy;

      // #1932: code is a panel slide — the logo sits on top in the corner,
      // so the panel extends to the full slide height (no vertical reserve).
      // #1932: panel-slide — logo in hoek, geen verticale reserve.
      expect(panelBottom, greaterThan(slideBottom - 50));
      expect(panelBottom, lessThanOrEqualTo(slideBottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('code uses the chosen monospace font family', (tester) async {
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(customMarkdown: 'void main() {}');
    const profile = ThemeProfile(
      codeFontFamily: 'Courier New',
      codeHighlightSyntax: false,
    );

    await tester.pumpWidget(_host(slide, profile));
    await tester.pump();

    final codeText = tester.widget<Text>(find.text('void main() {}'));
    expect(codeText.style?.fontFamily, 'Courier New');
    expect(tester.takeException(), isNull);
  });
}
