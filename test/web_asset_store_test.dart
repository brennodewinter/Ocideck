import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Future<Uint8List> _redPngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFF0000),
  );
  final img = await recorder.endRecording().toImage(8, 8);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  setUp(WebAssetStore.clear);
  tearDown(() {
    WebAssetStore.clear();
    WebAssetStore.overrideTotalBudgetForTest(null);
  });

  test('bewaart bytes onder een mem:-pad en vindt ze terug', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final path = WebAssetStore.put(bytes, name: 'foto.png');

    expect(WebAssetStore.isMemPath(path), isTrue);
    expect(WebAssetStore.bytesFor(path), same(bytes));
    expect(WebAssetStore.nameFor(path), 'foto.png');
    expect(WebAssetStore.totalBytes, bytes.length);
  });

  test('accepteert exact het totaalbudget en weigert de volgende byte', () {
    WebAssetStore.overrideTotalBudgetForTest(8);
    final exact = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      name: 'exact.png',
    );

    expect(WebAssetStore.totalBytes, 8);
    expect(
      () => WebAssetStore.put(Uint8List.fromList([9]), name: 'te-veel.png'),
      throwsA(
        isA<WebAssetBudgetExceeded>()
            .having((e) => e.usedBytes, 'usedBytes', 8)
            .having((e) => e.requestedBytes, 'requestedBytes', 1)
            .having((e) => e.maximumBytes, 'maximumBytes', 8),
      ),
    );
    expect(WebAssetStore.totalBytes, 8, reason: 'weigeren is atomair');
    expect(WebAssetStore.bytesFor(exact), isNotNull);
  });

  test('weigert één asset groter dan het hele budget zonder opslag', () {
    WebAssetStore.overrideTotalBudgetForTest(8);

    expect(
      () => WebAssetStore.put(Uint8List(9), name: 'veel-te-groot.bin'),
      throwsA(isA<WebAssetBudgetExceeded>()),
    );
    expect(WebAssetStore.isEmpty, isTrue);
    expect(WebAssetStore.totalBytes, 0);
  });

  test('een mislukte samengestelde put draait alleen nieuwe assets terug', () {
    WebAssetStore.overrideTotalBudgetForTest(4);
    final existing = WebAssetStore.put(
      Uint8List.fromList([9]),
      name: 'bestaand.png',
    );

    expect(
      () => WebAssetStore.atomic(() {
        WebAssetStore.put(Uint8List.fromList([1, 2]), name: 'eerste.png');
        WebAssetStore.put(Uint8List.fromList([3, 4]), name: 'tweede.png');
      }),
      throwsA(isA<WebAssetBudgetExceeded>()),
    );

    expect(WebAssetStore.totalBytes, 1);
    expect(WebAssetStore.bytesFor(existing), isNotNull);
    expect(WebAssetStore.nameFor(existing), 'bestaand.png');
  });

  test('het productieplafond is buiten web niet actief', () {
    WebAssetStore.overrideTotalBudgetForTest(null);
    expect(WebAssetStore.budgetEnforced, isFalse);
  });

  test('identieke inhoud deelt pad en telt maar eenmaal mee', () {
    final first = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3, 4]),
      name: 'eerste.png',
    );
    final duplicate = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3, 4]),
      name: 'kopie.png',
    );

    expect(duplicate, first);
    expect(WebAssetStore.totalBytes, 4);
    expect(WebAssetStore.nameFor(first), 'eerste.png');
  });

  test('een duplicaat past ook wanneer het budget al exact vol is', () {
    WebAssetStore.overrideTotalBudgetForTest(8);
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final first = WebAssetStore.put(bytes, name: 'eerste.png');

    expect(
      WebAssetStore.put(Uint8List.fromList(bytes), name: 'kopie.png'),
      first,
    );
    expect(WebAssetStore.totalBytes, 8);
  });

  test('onbekende of niet-mem-paden leveren niets op', () {
    expect(WebAssetStore.isMemPath('images/foto.png'), isFalse);
    expect(WebAssetStore.bytesFor('mem:bestaat-niet'), isNull);
    expect(WebAssetStore.bytesFor('images/foto.png'), isNull);
  });

  test('isEmpty volgt de inhoud', () {
    expect(WebAssetStore.isEmpty, isTrue);
    WebAssetStore.put(Uint8List.fromList([1]), name: 'a.png');
    expect(WebAssetStore.isEmpty, isFalse);
    WebAssetStore.clear();
    expect(WebAssetStore.isEmpty, isTrue);
  });

  test('retain houdt de opgegeven paden en gooit de rest weg', () {
    final keep = WebAssetStore.put(Uint8List.fromList([1]), name: 'keep.png');
    final drop = WebAssetStore.put(Uint8List.fromList([2]), name: 'drop.png');

    final removed = WebAssetStore.retain({keep});

    expect(removed, 1);
    expect(WebAssetStore.bytesFor(keep), isNotNull);
    expect(WebAssetStore.bytesFor(drop), isNull);
    expect(WebAssetStore.nameFor(drop), isNull, reason: 'ook de naam is weg');
    expect(WebAssetStore.totalBytes, 1);
  });

  test('retain met een lege verzameling maakt de store leeg', () {
    WebAssetStore.overrideTotalBudgetForTest(2);
    WebAssetStore.put(Uint8List.fromList([1]), name: 'a.png');
    WebAssetStore.put(Uint8List.fromList([2]), name: 'b.png');
    expect(WebAssetStore.retain(<String>{}), 2);
    expect(WebAssetStore.isEmpty, isTrue);
    expect(WebAssetStore.totalBytes, 0);
    expect(
      () => WebAssetStore.put(Uint8List.fromList([3, 4]), name: 'opnieuw.bin'),
      returnsNormally,
      reason: 'vrijgave geeft het volledige budget terug',
    );
    expect(WebAssetStore.totalBytes, 2);
  });

  test('retain van een gedeeld pad bewaart de bytes en hashadministratie', () {
    final first = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3]),
      name: 'a.png',
    );
    final duplicate = WebAssetStore.put(
      Uint8List.fromList([1, 2, 3]),
      name: 'b.png',
    );

    expect(WebAssetStore.retain({duplicate}), 0);
    expect(WebAssetStore.bytesFor(first), isNotNull);
    expect(
      WebAssetStore.put(Uint8List.fromList([1, 2, 3]), name: 'c.png'),
      first,
    );
    expect(WebAssetStore.totalBytes, 3);
  });

  testWidgets('een slide met mem:-pad rendert uit de store', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _redPngBytes();
      final memPath = WebAssetStore.put(bytes, name: 'rood.png');

      final slide = Slide(
        id: 'x',
        type: SlideType.image,
        title: 'In-memory afbeelding',
        imagePath: memPath,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(slide: slide),
            ),
          ),
        ),
      );
      await tester.pump();

      // De preview moet een echte Image tekenen (geen placeholder-icoon)
      // waarvan de capped provider onze bytes als cache-sleutel draagt.
      final images = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (w) =>
                w.image is CappedImage &&
                identical((w.image as CappedImage).cacheKey, bytes),
          );
      expect(images, isNotEmpty, reason: 'mem:-afbeelding moet renderen');
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });
  });
}
