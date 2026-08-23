import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(slide: slide),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('two-bullet columns render their optional headings', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.twoBullets).copyWith(
      title: 'Vergelijking',
      columnTitle1: 'Voordelen',
      columnTitle2: 'Nadelen',
      bullets: const ['Snel', 'Goedkoop'],
      bullets2: const ['Complex'],
    );

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(find.text('Voordelen'), findsOneWidget);
    expect(find.text('Nadelen'), findsOneWidget);
    // Heading sits above the bullets of its column.
    final headingTop = tester.getTopLeft(find.text('Voordelen')).dy;
    final bulletTop = tester.getTopLeft(find.text('Snel')).dy;
    expect(headingTop, lessThan(bulletTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-bullet columns without headings render no heading text', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.twoBullets).copyWith(
      title: 'Geen koppen',
      bullets: const ['Links'],
      bullets2: const ['Rechts'],
    );

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Rechts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-bullet columns use the same font size', (tester) async {
    final slide = Slide.create(SlideType.twoBullets).copyWith(
      bullets: const ['Solo'],
      bullets2: List.generate(14, (i) => 'Item $i'),
    );

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    double sizeOf(String text) => tester
        .widget<InlineMarkdownText>(
          find.byWidgetPredicate(
            (x) => x is InlineMarkdownText && x.text == text,
          ),
        )
        .style
        .fontSize!;

    expect(sizeOf('Solo'), sizeOf('Item 0'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short bullet lists grow but respect the body-text maximum', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Kort', bullets: const ['Eén punt', 'Twee punten']);

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    final size = tester
        .widget<InlineMarkdownText>(
          find.byWidgetPredicate(
            (x) => x is InlineMarkdownText && x.text == 'Eén punt',
          ),
        )
        .style
        .fontSize!;
    // Auto-fit still grows the text beyond its design size (w * 0.026)…
    expect(size, greaterThan(800 * 0.026));
    // …but never past ≈32pt-on-a-16:9-deck (w * 0.0335), so the body text
    // keeps a clear distance from the title.
    expect(size, lessThanOrEqualTo(800 * 0.0335 + 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bullets slide renders an optional subheading below the title', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Agenda',
      subtitle: 'Vandaag',
      bullets: const ['Punt een', 'Punt twee'],
    );

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Vandaag'), findsOneWidget);
    final titleTop = tester.getTopLeft(find.text('Agenda')).dy;
    final subTop = tester.getTopLeft(find.text('Vandaag')).dy;
    final bulletTop = tester.getTopLeft(find.text('Punt een')).dy;
    expect(titleTop, lessThan(subTop));
    expect(subTop, lessThan(bulletTop));
    expect(tester.takeException(), isNull);
  });
}
