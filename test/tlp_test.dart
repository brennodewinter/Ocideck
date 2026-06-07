import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  group('TlpLevel', () {
    test('labels follow the FIRST TLP 2.0 spelling', () {
      expect(TlpLevel.none.label, '');
      expect(TlpLevel.clear.label, 'TLP:CLEAR');
      expect(TlpLevel.green.label, 'TLP:GREEN');
      expect(TlpLevel.amber.label, 'TLP:AMBER');
      expect(TlpLevel.amberStrict.label, 'TLP:AMBER+STRICT');
      expect(TlpLevel.red.label, 'TLP:RED');
    });

    test('menu label shows "Geen" for none', () {
      expect(TlpLevel.none.menuLabel, 'Geen');
      expect(TlpLevel.red.menuLabel, 'TLP:RED');
    });

    test('key round-trips through fromKey for every level', () {
      for (final level in TlpLevel.values) {
        expect(TlpLevelX.fromKey(level.key), level);
      }
    });

    test('fromKey is forgiving and defaults to none', () {
      expect(TlpLevelX.fromKey('AMBER+STRICT'), TlpLevel.amberStrict);
      expect(TlpLevelX.fromKey('amberstrict'), TlpLevel.amberStrict);
      expect(TlpLevelX.fromKey('onzin'), TlpLevel.none);
      expect(TlpLevelX.fromKey(''), TlpLevel.none);
    });
  });

  group('slideVisibleAtTlp', () {
    Slide slideAt(TlpLevel level) =>
        Slide.create(SlideType.bullets).copyWith(tlp: level);

    test('an unclassified slide is always visible', () {
      for (final level in TlpLevel.values) {
        expect(slideVisibleAtTlp(slideAt(TlpLevel.none), level), isTrue);
      }
    });

    test('a slide stricter than the presentation is withheld', () {
      // Presentation at GREEN: CLEAR/GREEN shown, AMBER/RED withheld.
      expect(
        slideVisibleAtTlp(slideAt(TlpLevel.clear), TlpLevel.green),
        isTrue,
      );
      expect(
        slideVisibleAtTlp(slideAt(TlpLevel.green), TlpLevel.green),
        isTrue,
      );
      expect(
        slideVisibleAtTlp(slideAt(TlpLevel.amber), TlpLevel.green),
        isFalse,
      );
      expect(slideVisibleAtTlp(slideAt(TlpLevel.red), TlpLevel.green), isFalse);
    });

    test('a RED presentation shows every slide', () {
      for (final level in TlpLevel.values) {
        expect(slideVisibleAtTlp(slideAt(level), TlpLevel.red), isTrue);
      }
    });

    test('an unset presentation only shows unclassified slides', () {
      expect(slideVisibleAtTlp(slideAt(TlpLevel.none), TlpLevel.none), isTrue);
      expect(
        slideVisibleAtTlp(slideAt(TlpLevel.clear), TlpLevel.none),
        isFalse,
      );
    });
  });

  group('TLP marking on slides', () {
    Widget host(TlpLevel tlp) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: Slide.create(
                SlideType.bullets,
              ).copyWith(title: 'T', bullets: ['a']),
              tlp: tlp,
            ),
          ),
        ),
      ),
    );

    testWidgets('renders the marking when a level is set', (tester) async {
      await tester.pumpWidget(host(TlpLevel.red));
      await tester.pump();
      expect(find.text('TLP:RED'), findsOneWidget);
    });

    testWidgets('renders nothing when none', (tester) async {
      await tester.pumpWidget(host(TlpLevel.none));
      await tester.pump();
      expect(find.textContaining('TLP:'), findsNothing);
    });

    testWidgets('right-side image caption aligns with the TLP badge', (
      tester,
    ) async {
      const caption = 'Foto: iemand';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 450,
                child: SlidePreviewWidget(
                  slide: Slide.create(
                    SlideType.bulletsImage,
                  ).copyWith(title: 'T', bullets: ['a'], imageCaption: caption),
                  tlp: TlpLevel.red,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final captionRight = tester.getTopRight(find.text(caption)).dx;
      final tlpRight = tester.getTopRight(find.text('TLP:RED')).dx;

      expect(
        (captionRight - tlpRight).abs(),
        lessThan(4),
        reason: 'Caption and TLP badge should share the same right edge.',
      );
    });
  });
}
