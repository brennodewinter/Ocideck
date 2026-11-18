import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';

void main() {
  for (final slideCount in [20, 21, 41]) {
    testWidgets(
      '$slideCount slides complete while a loading indicator animates',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Center(child: CircularProgressIndicator())),
        );
        final deck = Deck(
          title: 'Opening',
          slides: List.generate(
            slideCount,
            (_) => Slide.create(SlideType.title),
          ),
        );
        var completed = false;
        // Gebruik de echte event loop: een achtergebleven idle-taak blijft in
        // fakeAsync Timer.run posten, waardoor zelfs pump niet meer terugkeert.
        try {
          await tester.runAsync(() async {
            await const SlideQualityAnalyzer()
                .analyzeWarmed(deck)
                .timeout(const Duration(seconds: 2));
            completed = true;
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(tester.takeException(), isNull);
        expect(completed, isTrue);
      },
    );
  }
}
