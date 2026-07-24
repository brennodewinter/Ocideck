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

  /// Tweede tekstniveau: kolomkoppen, timerlabels, sneltoetshints, de
  /// slidenummers in het overzicht, de melding dat een dia geen notities heeft.
  ///
  /// Bestaat sinds #780. Deze regels stonden er als `Colors.white24`, `white30`
  /// en `white38` — 2,2 tot 3,6:1, en de sneltoetsbalk in presenter-view is de
  /// énige uitleg die een presentator tijdens een presentatie op het scherm
  /// heeft. Een derde, nóg zwakker tekstniveau bestaat hier bewust niet: op een
  /// oppervlak van #0A0A0A tot #3A3A3A is dit de dunste grijstint die 4,5:1
  /// haalt, dus een tint daaronder kán geen tekst zijn.
  static const textMuted = Color(0xFFADADAD);

  /// Een keuze-affordance of scheidingslijn: de ring om een niet-gekozen
  /// inkkleur, de streepjes tussen de gereedschapsgroepen.
  ///
  /// Gemeten tegen de annotatiebalk in z'n lichtste stand (zwart op 82% over een
  /// witte dia, #2E2E2E), want daar is het contrast het krapst. Draagt geen
  /// tekst, dus de lat is 3:1 (WCAG 1.4.11) — en de zwarte inkkleur is op deze
  /// balk alleen aan deze ring te herkennen.
  static const outline = Color(0xFF8C8C8C);

  // Annotatie-/laserink
  static const laserGreen = Color(0xFF22C55E);
  static const laserRed = Color(0xFFFF3B30);
}
