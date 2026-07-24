import 'package:flutter/material.dart';

/// Het bewust donkere kleurenpalet van de afbeeldingskiezer (coverflow/grid).
///
/// Dit is een op zichzelf staande donkere chrome — géén onderdeel van het
/// lichte app-thema. Daarom een eigen palet in plaats van [AppTheme]-tokens;
/// de conventie-ratchet op rauwe `Color(0x…)` zondert dit bestand bewust uit.
///
/// Die uitzondering had een prijs (#779): omdat dit palet buiten het thema
/// staat, viel het ook buiten élke contrastmeting. Zeven teksten stonden
/// daardoor onder de AA-lat. `test/standalone_palette_contrast_test.dart` dekt
/// dat nu — en die toets is de reden dat de tokens hieronder hun rol in hun
/// naam dragen: een `icon…` mag 3:1 (WCAG 1.4.11), een `text…` moet 4,5:1.
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

  // Tekst — lat 4,5:1 op het oppervlak waar ze op liggen (WCAG 1.4.3).
  static const text = Color(0xFFCDD9E5);
  static const textMuted = Color(0xFF8B949E);

  /// De gedempte tint voor **iconen**, niet voor tekst.
  ///
  /// Heette `textDim` en kleurde beide. Als tekst haalde die op geen enkel
  /// oppervlak van dit palet de 4,5:1 — tussen 3,31 (op [surface2]) en 4,24
  /// (op [bgDeepest]) — en dat trof onder meer de twee lege-toestandregels die
  /// juist uitleggen hoe je verder komt, en de zoekhint. Als icoon is 3:1 de
  /// lat (WCAG 1.4.11 voor grafische onderdelen) en dat haalt hij overal.
  ///
  /// De naam draagt nu de regel, want een `textDim` die geen tekst mag kleuren
  /// is een val voor de volgende die hem gebruikt (#779). Tekst die gedempt
  /// moet lijken, neemt [textMuted] — die haalt op elk oppervlak hier ten
  /// minste 4,95:1 en blijft ruim onderscheidbaar van [text].
  static const iconDim = Color(0xFF6E7681);

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
