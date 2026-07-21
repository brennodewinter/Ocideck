import 'package:flutter/material.dart';

/// Het bewust donkere kleurenpalet van de afbeeldingskiezer (coverflow/grid).
///
/// Dit is een op zichzelf staande donkere chrome — géén onderdeel van het
/// lichte app-thema. Daarom een eigen palet in plaats van [AppTheme]-tokens;
/// de conventie-ratchet op rauwe `Color(0x…)` zondert dit bestand bewust uit.
abstract final class ImagePickerPalette {

  // Oppervlakken (donker → lichter)
  static const bgDeepest = Color(0xFF080D14);
  static const bgDeep = Color(0xFF0B0F16);
  static const bg = Color(0xFF0D1117);
  static const overlay = Color(0xFF161D2B);
  static const surface1 = Color(0xFF161B22);
  static const surfaceAlt = Color(0xFF1D2433);
  static const surface2 = Color(0xFF21262D);

  // Randen
  static const border = Color(0xFF30363D);
  static const borderStrong = Color(0xFF484F58);

  // Tekst
  static const text = Color(0xFFCDD9E5);
  static const textMuted = Color(0xFF8B949E);
  static const textDim = Color(0xFF6E7681);

  // Accenten / status
  static const accent = Color(0xFF58A6FF);
  static const accentStrong = Color(0xFF1D4ED8);
  static const success = Color(0xFF22C55E);
  static const successStrong = Color(0xFF238636);
  static const warning = Color(0xFFF0B429);
  static const danger = Color(0xFFE5534B);
  static const dangerSoft = Color(0xFFE5746E);
  static const dangerStrong = Color(0xFFB62324);
}
