import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

import 'support/pump_until.dart';

void main() {
  testWidgets('opening a deck while a document image loads completes both', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ocideck-document-image-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/images').createSync();
    File('${dir.path}/images/photo.png').writeAsBytesSync(
      Uint8List.fromList(img.encodePng(img.Image(width: 30, height: 20))),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: DocumentImage(
              source: 'images/photo.png',
              alt: 'photo',
              projectPath: dir.path,
            ),
          ),
        ),
      ),
    );
    // De documentafbeelding is nog aan het laden wanneer een presentatie
    // wordt geopend. Die laadindicator mag de voorcontrole niet blokkeren.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final deck = Deck(
      title: 'Opening beside a document',
      slides: List.generate(21, (_) => Slide.create(SlideType.title)),
    );
    await tester.runAsync(
      () => const SlideQualityAnalyzer()
          .analyzeWarmed(deck)
          .timeout(const Duration(seconds: 2)),
    );
    bool hasDecodedImage() => find
        .byType(RawImage)
        .evaluate()
        .any((e) => (e.widget as RawImage).image != null);
    await pumpUntil(tester, hasDecodedImage);
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(hasDecodedImage(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
