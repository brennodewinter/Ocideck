import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
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
  group('group-heading model helpers', () {
    test('round-trip through the marker', () {
      final h = groupHeadingBullet('Ochtend');
      expect(isGroupHeading(h), isTrue);
      expect(groupHeadingText(h), 'Ochtend');
      expect(isGroupHeading('Gewone bullet'), isFalse);
      expect(isGroupHeading('\t[x] Taak'), isFalse);
    });

    test('a wordless heading is a divider (empty label)', () {
      final h = groupHeadingBullet('');
      expect(isGroupHeading(h), isTrue);
      expect(groupHeadingText(h), '');
      // It is not blank text, so list filters keep it.
      expect(h.trimLeft().isNotEmpty, isTrue);
    });

    test('a heading is never a checked/labelled checklist item', () {
      final h = groupHeadingBullet('Blok');
      expect(checklistItemChecked(h), isFalse);
    });
  });

  group('group-heading layout metrics', () {
    test('a heading has no list marker and does not consume a number', () {
      final items = [groupHeadingBullet('Kop'), 'Een', 'Twee'];
      expect(bulletListMarker(items, 0, ListStyle.numbered), '');
      // The heading did not take number 1 — the first real item does.
      expect(bulletListMarker(items, 1, ListStyle.numbered), '1.');
      expect(bulletListMarker(items, 2, ListStyle.numbered), '2.');
    });

    test('a heading adds height to the measured block', () {
      double blockHeight(List<String> bullets) => bulletsBlockHeight(
        scale: 1,
        availW: 600,
        hasTitle: false,
        title: '',
        bullets: bullets,
        titleSize: 40,
        bulletSize: 24,
        spacing: 20,
        bulletGap: 4,
        font: 'Arial',
      );
      final withoutHeading = blockHeight(['Een', 'Twee']);
      final withHeading = blockHeight([
        'Een',
        groupHeadingBullet('Kop'),
        'Twee',
      ]);
      expect(withHeading, greaterThan(withoutHeading));
    });
  });

  group('group-heading rendering', () {
    testWidgets('a labelled heading renders above the bullets it introduces', (
      tester,
    ) async {
      final slide = Slide.create(SlideType.bullets).copyWith(
        title: 'Agenda',
        bullets: [
          groupHeadingBullet('Ochtend'),
          'Inloop',
          groupHeadingBullet('Middag'),
          'Workshops',
        ],
      );

      await tester.pumpWidget(_host(slide));
      await tester.pump();

      expect(find.text('Ochtend'), findsOneWidget);
      expect(find.text('Middag'), findsOneWidget);
      final middagTop = tester.getTopLeft(find.text('Middag')).dy;
      final workshopsTop = tester.getTopLeft(find.text('Workshops')).dy;
      expect(middagTop, lessThan(workshopsTop));
      expect(tester.takeException(), isNull);
    });

    testWidgets('headings render in a bullets+image slide', (tester) async {
      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        title: 'Programma',
        bullets: [
          groupHeadingBullet('Ochtend'),
          'Inloop',
          groupHeadingBullet('Middag'),
          'Workshops',
        ],
      );

      await tester.pumpWidget(_host(slide));
      await tester.pump();

      expect(find.text('Ochtend'), findsOneWidget);
      expect(find.text('Middag'), findsOneWidget);
      final middagTop = tester.getTopLeft(find.text('Middag')).dy;
      final workshopsTop = tester.getTopLeft(find.text('Workshops')).dy;
      expect(middagTop, lessThan(workshopsTop));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wordless divider renders without overflowing', (
      tester,
    ) async {
      final slide = Slide.create(SlideType.bullets).copyWith(
        title: 'Delen',
        bullets: ['Boven de streep', groupHeadingBullet(''), 'Onder de streep'],
      );

      await tester.pumpWidget(_host(slide));
      await tester.pump();

      expect(find.text('Boven de streep'), findsOneWidget);
      expect(find.text('Onder de streep'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
