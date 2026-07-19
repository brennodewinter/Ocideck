// De beeldcontrole op een platform zonder native detector — in de praktijk het
// web, waar FFI niet bestaat.
//
// Deze variant meldt eerlijk dat hij niets kan in plaats van nul gezichten terug
// te geven. Dat verschil is de hele reden dat [ImageFaceScanner.isSupported]
// bestaat: "wij hebben niets gevonden" en "hier is niet gekeken" mogen nooit op
// elkaar lijken. Het paneel met uitgevoerde controles leest die vlag en laat de
// beeldcontrole weg wanneer ze niet draaide.

import 'dart:typed_data';

import 'image_face_scan.dart';

class _UnsupportedImageFaceScanner implements ImageFaceScanner {
  const _UnsupportedImageFaceScanner();

  @override
  bool get isSupported => false;

  @override
  Future<int> countFaces(Uint8List imageBytes) async => 0;

  @override
  void dispose() {}
}

ImageFaceScanner createPlatformImageFaceScanner(Uint8List modelBytes) =>
    const _UnsupportedImageFaceScanner();
