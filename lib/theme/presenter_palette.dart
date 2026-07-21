import 'package:flutter/material.dart';

/// Het donkere kleurenpalet van de volledig-scherm presentatiemodus
/// (presenter-view, overlays, ink/annotaties).
///
/// Net als [ImagePickerPalette] een op zichzelf staande donkere chrome — géén
/// onderdeel van het lichte app-thema, daarom een eigen palet dat de
/// raw-colour-ratchet uitzondert.
abstract final class PresenterPalette {

  // Oppervlakken (donker → lichter)
  static const bgDeepest = Color(0xFF0A0A0A);
  static const bg = Color(0xFF141414);
  static const bg2 = Color(0xFF161616);
  static const surface = Color(0xFF1F1F1F);
  static const surface2 = Color(0xFF262626);
  static const surface3 = Color(0xFF2A2A2A);
  static const surface4 = Color(0xFF3A3A3A);

  // Tekst op donker
  static const text = Color(0xFFE5E5E5);

  // Annotatie-/laserink
  static const laserGreen = Color(0xFF22C55E);
  static const laserRed = Color(0xFFFF3B30);
}
