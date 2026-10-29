import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_limits.dart';

void main() {
  group('decodeEdgeForBox', () {
    test('800 logische px bij DPR 2 rondt af op 2048', () {
      expect(decodeEdgeForBox(800, 450, 2), 2048);
    });

    test('1920 logische px bij DPR 1 rondt af op 2048', () {
      expect(decodeEdgeForBox(1920, 1080, 1), 2048);
    });

    test('een klein vak blijft op de laagste trede', () {
      expect(decodeEdgeForBox(400, 225, 1), 1024);
    });

    test('een 4K-vak blijft op het plafond', () {
      expect(decodeEdgeForBox(3840, 2160, 1), kMaxImageDecodeDimension);
    });
  });

  test('een decodegrens van 2048 vraagt geen groter doel dan 2048', () async {
    final provider =
        cappedMemoryImage(Uint8List(8), maxEdge: 2048) as CappedImage;
    ui.TargetImageSize? seen;
    provider.loadImage(provider, (buffer, {getTargetSize}) async {
      seen = getTargetSize?.call(6000, 4000);
      throw StateError('stop');
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isNotNull);
    expect(seen!.width, lessThanOrEqualTo(2048));
    expect(seen!.height, lessThanOrEqualTo(2048));
    // Binnen de trede blijft het doel leeg: dat is wat een GIF laat animeren.
    ui.TargetImageSize? native;
    provider.loadImage(provider, (buffer, {getTargetSize}) async {
      native = getTargetSize?.call(800, 600);
      throw StateError('stop');
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(native!.width, isNull);
    expect(native!.height, isNull);
  });

  testWidgets('preview op 800 px bij DPR 2 kiest trede 2048', (tester) async {
    final plan = await _planFor(tester, const Size(800, 450), 2);
    expect(plan.edge, lessThanOrEqualTo(2048));
    expect(plan.edge, 2048);
    expect(plan.hardResize, isFalse);
  });

  testWidgets('presentatie op 1920 px bij DPR 1 kiest trede 2048', (
    tester,
  ) async {
    final plan = await _planFor(tester, const Size(1920, 1080), 1);
    expect(plan.edge, lessThanOrEqualTo(2048));
    expect(plan.hardResize, isFalse);
  });

  testWidgets('een expliciete miniatuurgrens blijft ResizeImage', (
    tester,
  ) async {
    final plan = await _planFor(
      tester,
      const Size(180, 100),
      2,
      explicitEdge: 512,
    );
    expect(plan.edge, 512);
    expect(plan.hardResize, isTrue);
  });
}

Future<DecodePlan> _planFor(
  WidgetTester tester,
  Size size,
  double devicePixelRatio, {
  int? explicitEdge,
}) async {
  DecodePlan? plan;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: devicePixelRatio, size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: ResolvedDecodeImage(
              explicitEdge: explicitEdge,
              imageFor: (next) {
                plan = next;
                return cappedMemoryImage(Uint8List(1), maxEdge: next.edge);
              },
              child: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  return plan!;
}
