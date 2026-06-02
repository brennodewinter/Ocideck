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
  });
}
