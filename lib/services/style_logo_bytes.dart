// Of gekozen logobytes in een stijlprofiel mogen.
//
// Een logo is klein en blijft lang hangen: in het profiel, in een pakket en
// op web in het sessiegeheugen. De gewone afbeeldingsgrens (64 MB) is daar
// te ruim, en een bestand dat geen afbeelding is mag geen pad worden dat
// later als logo wordt getekend.
import 'dart:typed_data';

import '../utils/image_signature.dart';
import 'file_service.dart';

/// De bytes wanneer ze een stijllogo mogen zijn, anders `null`.
///
/// Leeg, groter dan [FileService.maxStyleProfileLogoBytes], of zonder een
/// bekende afbeeldingshandtekening valt af. De aanroeper kiest de melding.
Uint8List? styleLogoFromBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > FileService.maxStyleProfileLogoBytes) {
    return null;
  }
  if (imageMimeFromBytes(bytes) == null) return null;
  return bytes;
}
