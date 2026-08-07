import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Het kleurenpalet van de afbeeldingskiezer (coverflow/grid).
///
/// Was een op zichzelf staande **donkere** chrome, los van het app-thema.
/// Daardoor botste de kiezer in de lichte app-modus met de rest (een donkere
/// modal op een licht venster). De tokens zijn nu **mode-afhankelijk**: in de
/// lichte modus lichte oppervlakken met donkere tekst, in de donkere modus exact
/// het oude palet. Zo volgt de kiezer het gekozen app-appearance-profiel, net als
/// [AppTheme]. De conventie-ratchet op rauwe `Color(0x…)` zondert dit bestand nog
/// steeds uit — een palet mág kleurwaarden dragen.
///
/// Omdat de tokens getters zijn (niet const), moet een `const`-context die zo'n
/// token gebruikt zijn `const` laten vallen — dezelfde regel als bij [AppTheme].
///
/// Contrast (#779): omdat dit palet ooit buiten élke contrastmeting viel, stonden
/// zeven teksten onder de AA-lat. `test/standalone_palette_contrast_test.dart`
/// dekt dat nu — in **beide** thema's — en die toets is de reden dat de tokens
/// hun rol in hun naam dragen: een `icon…` mag 3:1 (WCAG 1.4.11), een `text…`
/// moet 4,5:1.
abstract final class ImagePickerPalette {
  /// Kies [light] of [dark] afhankelijk van het app-thema.
  static Color _m(Color light, Color dark) => AppTheme.isDark ? dark : light;

  // Oppervlakken (van het meest verzonken naar het lichtste kaartoppervlak).
  static Color get bgDeepest =>
      _m(const Color(0xFFE7EBF1), const Color(0xFF080D14));
  static Color get bgDeep =>
      _m(const Color(0xFFEDF0F5), const Color(0xFF0B0F16));
  static Color get bg => _m(const Color(0xFFF5F7FA), const Color(0xFF0D1117));
  static Color get overlay =>
      _m(const Color(0xFFEDF0F5), const Color(0xFF161D2B));
  static Color get surface1 =>
      _m(const Color(0xFFFFFFFF), const Color(0xFF161B22));
  static Color get surfaceAlt =>
      _m(const Color(0xFFE7ECF5), const Color(0xFF1D2433));
  static Color get surface2 =>
      _m(const Color(0xFFE6E9ED), const Color(0xFF21262D));

  // Randen
  static Color get border =>
      _m(const Color(0xFFD0D7DE), const Color(0xFF30363D));
  static Color get borderStrong =>
      _m(const Color(0xFFAEB6C0), const Color(0xFF484F58));

  // Tekst — lat 4,5:1 op het oppervlak waar ze op liggen (WCAG 1.4.3).
  static Color get text => _m(const Color(0xFF1F2328), const Color(0xFFCDD9E5));
  static Color get textMuted =>
      _m(const Color(0xFF57606A), const Color(0xFF8B949E));

  /// De gedempte tint voor **iconen**, niet voor tekst.
  ///
  /// Heette `textDim` en kleurde beide. Als tekst haalde die op geen enkel
  /// oppervlak van dit palet de 4,5:1 (#779). Als icoon is 3:1 de lat (WCAG
  /// 1.4.11 voor grafische onderdelen) en dat haalt hij overal — in beide
  /// thema's. De naam draagt de regel, want een `textDim` die geen tekst mag
  /// kleuren is een val voor de volgende die hem gebruikt.
  static Color get iconDim =>
      _m(const Color(0xFF6E7781), const Color(0xFF6E7681));

  // Accenten / status. De vullingen (accentStrong/successStrong/dangerStrong)
  // dragen een wit label en blijven daarom themaloos vast; de tekst/icoon-tinten
  // (accent/success/warning/danger/dangerSoft) worden in de lichte modus donker
  // genoeg om op een licht oppervlak te lezen.
  static Color get accent =>
      _m(const Color(0xFF0969DA), const Color(0xFF58A6FF));
  static const accentStrong = Color(0xFF1D4ED8);
  static Color get success =>
      _m(const Color(0xFF1A7F37), const Color(0xFF22C55E));
  static const successStrong = Color(0xFF238636);
  static Color get warning =>
      _m(const Color(0xFF9A6700), const Color(0xFFF0B429));
  static Color get danger =>
      _m(const Color(0xFFCF222E), const Color(0xFFE5534B));
  static Color get dangerSoft =>
      _m(const Color(0xFFC4342B), const Color(0xFFE5746E));
  static const dangerStrong = Color(0xFFB62324);
}
