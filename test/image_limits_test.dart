import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_limits.dart';

void main() {
  group('cappedDecodeTarget', () {
    test('within the cap decodes at native resolution (null target)', () {
      // A native target is what keeps an animated GIF/WebP animating instead of
      // freezing on its first frame, so this is the important case.
      expect(cappedDecodeTarget(800, 600), (width: null, height: null));
      expect(
        cappedDecodeTarget(kMaxImageDecodeDimension, kMaxImageDecodeDimension),
        (width: null, height: null),
      );
      expect(cappedDecodeTarget(1, 1), (width: null, height: null));
    });

    test('a wide over-cap image scales its width to the cap, aspect kept', () {
      final t = cappedDecodeTarget(8192, 4096);
      expect(t.width, kMaxImageDecodeDimension);
      expect(t.height, 2048); // 4096 / (8192/4096)
    });

    test('a tall over-cap image scales its height to the cap, aspect kept', () {
      final t = cappedDecodeTarget(4096, 8192);
      expect(t.height, kMaxImageDecodeDimension);
      expect(t.width, 2048);
    });

    test('a huge square clamps both axes to the cap', () {
      expect(cappedDecodeTarget(30000, 30000), (
        width: kMaxImageDecodeDimension,
        height: kMaxImageDecodeDimension,
      ));
    });

    test('only one axis over the cap still triggers a downscale', () {
      final t = cappedDecodeTarget(5000, 100);
      expect(t.width, kMaxImageDecodeDimension);
      expect(t.height, greaterThanOrEqualTo(1));
    });

    test('degenerate zero dimensions fall back to native', () {
      expect(cappedDecodeTarget(0, 100), (width: null, height: null));
      expect(cappedDecodeTarget(100, 0), (width: null, height: null));
    });
  });
}
