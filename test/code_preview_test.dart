import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
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
    'syntax highlighting on uses HighlightView for a known language',
    (tester) async {
      final slide = Slide.create(
        SlideType.code,
      ).copyWith(codeLanguage: 'dart', customMarkdown: 'void main() {}');
      const profile = ThemeProfile(codeHighlightSyntax: true);

      await tester.pumpWidget(_host(slide, profile));
      await tester.pump();

      expect(find.byType(HighlightView), findsOneWidget);
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
    expect(find.byType(HighlightView), findsNothing);
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
