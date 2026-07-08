import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/utils/image_limits.dart';

/// Builds a real 2-frame animated GIF (red → green) so we can assert how the
/// decode path treats a multi-frame image.
Uint8List _twoFrameGif() {
  final frame1 = img.Image(width: 8, height: 8, numChannels: 3);
  img.fill(frame1, color: img.ColorRgb8(255, 0, 0));
  final frame2 = img.Image(width: 8, height: 8, numChannels: 3);
  img.fill(frame2, color: img.ColorRgb8(0, 255, 0));
  frame1.frames.add(frame2); // frame1 itself is frames[0]; now 2 frames total
  return img.encodeGif(frame1);
}

Future<ui.Codec> _decodeWith(
  Uint8List bytes,
  ui.TargetImageSizeCallback getTargetSize,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  return ui.instantiateImageCodecWithSize(buffer, getTargetSize: getTargetSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the fixture really is a 2-frame animation', () {
    final decoded = img.decodeGif(_twoFrameGif());
    expect(decoded, isNotNull);
    expect(decoded!.frames.length, 2);
  });

  test(
    'within-cap decode keeps every frame (animated GIF stays animated)',
    () async {
      final gif = _twoFrameGif();
      // 8×8 is well within the cap, so cappedDecodeTarget returns a null target
      // → the deck's capped provider decodes at native resolution, exactly like
      // a plain FileImage/Image, and the codec keeps both frames. (A concrete
      // decode target — what ResizeImage always passes — is what freezes an
      // animated GIF on its first frame on the production renderer.)
      final codec = await _decodeWith(gif, (w, h) {
        final t = cappedDecodeTarget(w, h);
        return ui.TargetImageSize(width: t.width, height: t.height);
      });
      expect(codec.frameCount, 2);
    },
  );
}
