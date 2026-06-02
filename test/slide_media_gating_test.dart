import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De audioknop mag alleen verschijnen wanneer media bewust is ingeschakeld.
/// Zo dreunen thumbnails en de export niet door (de kern van "muziek kun je
/// niet uitzetten op een slide").
void main() {
  Future<void> pump(WidgetTester tester, {required bool enableMedia}) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(audioPath: '/tmp/does_not_exist.mp3');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: SlidePreviewWidget(slide: slide, enableMedia: enableMedia),
          ),
        ),
      ),
    );
  }

  testWidgets('no audio control when media is disabled (thumbnails/export)', (
    tester,
  ) async {
    await pump(tester, enableMedia: false);
    expect(find.byTooltip('Audio'), findsNothing);
  });

  testWidgets('audio control appears when media is enabled', (tester) async {
    await pump(tester, enableMedia: true);
    expect(find.byTooltip('Audio'), findsOneWidget);
  });
}
