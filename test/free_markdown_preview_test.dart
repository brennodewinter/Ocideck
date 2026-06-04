import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(slide: slide),
      ),
    ),
  );
}

void main() {
  testWidgets('free Markdown renders a highlighted code block', (tester) async {
    final slide = Slide.create(SlideType.freeMarkdown).copyWith(
      customMarkdown: '# Demo\n\n```dart\nvoid main() => print(42);\n```\n',
    );
    await tester.pumpWidget(_host(slide));

    expect(find.byType(HighlightView), findsOneWidget);
  });

  testWidgets('free Markdown renders display math', (tester) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: 'Stelling:\n\n\$\$E = mc^2\$\$\n');
    await tester.pumpWidget(_host(slide));

    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('an unknown code language falls back without throwing', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: '```nonexistentlang\nsome code\n```\n');
    await tester.pumpWidget(_host(slide));

    // No HighlightView (unknown language) and no exception during build.
    expect(find.byType(HighlightView), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('some code'), findsOneWidget);
  });
}
