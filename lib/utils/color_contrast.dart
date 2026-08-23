import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Parses a hex colour string (`#RRGGBB` or `RRGGBB`). Returns `null` when
/// invalid so callers can skip the pair instead of throwing.
///
/// Dit is bewust de *strenge* variant: alleen zes tekens, altijd dekkend, en
/// `null` bij twijfel. Wie een kleur nodig heeft die er altijd is, neemt
/// `AppTheme.parseHexColor` — die valt terug in plaats van te weigeren. Het
/// naamsverschil (`tryParse…` versus `parse…`) volgt de Dart-afspraak en is
/// het enige waaraan je de twee contracten uit elkaar houdt.
Color? tryParseHexColor(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  var hex = value.trim();
  if (!hex.startsWith('#')) hex = '#$hex';
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
}

/// WCAG 2.1 relative luminance contrast ratio between two sRGB colours.
double contrastRatio(Color foreground, Color background) {
  final l1 = foreground.computeLuminance();
  final l2 = background.computeLuminance();
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Returns the contrast ratio for a hex pair, or `null` when either colour is
/// invalid.
double? hexContrastRatio(String foreground, String background) {
  final fg = tryParseHexColor(foreground);
  final bg = tryParseHexColor(background);
  if (fg == null || bg == null) return null;
  return contrastRatio(fg, bg);
}

/// WCAG 2.1 level AA thresholds.
const double kWcagAaNormalText = 4.5;
const double kWcagAaLargeText = 3.0;

/// Body text below this ratio is treated as a hard quality error.
const double kWcagCriticalBodyText = 3.0;

bool meetsWcagAa(
  String foreground,
  String background, {
  bool largeText = false,
}) {
  final ratio = hexContrastRatio(foreground, background);
  if (ratio == null) return true;
  final threshold = largeText ? kWcagAaLargeText : kWcagAaNormalText;
  return ratio >= threshold;
}

/// Blends [foreground] over [background] and returns the WCAG contrast ratio.
double? blendedHexContrastRatio(
  String foreground,
  String background, {
  required double foregroundAlpha,
}) {
  final fg = tryParseHexColor(foreground);
  final bg = tryParseHexColor(background);
  if (fg == null || bg == null) return null;
  final blended = Color.alphaBlend(
    fg.withValues(alpha: foregroundAlpha.clamp(0.0, 1.0)),
    bg,
  );
  return contrastRatio(blended, bg);
}

/// Returns the smallest RGB shift of [foreground] that reaches [minRatio]
/// against [background]. The hue is retained as far as possible by moving only
/// along the straight line towards black or white; both directions are tried
/// and the visually nearest result wins.
///
/// [foregroundAlpha] models colours that are actually painted translucent
/// (footer/subtitle text). Invalid input is returned unchanged.
String nearestContrastingHex(
  String foreground,
  String background, {
  required double minRatio,
  double foregroundAlpha = 1,
}) {
  final fg = tryParseHexColor(foreground);
  final bg = tryParseHexColor(background);
  if (fg == null || bg == null) return foreground;
  final alpha = foregroundAlpha.clamp(0.0, 1.0);
  double ratio(Color color) =>
      contrastRatio(Color.alphaBlend(color.withValues(alpha: alpha), bg), bg);
  if (ratio(fg) >= minRatio) return _hex(fg);

  Color? candidate(Color target) {
    if (ratio(target) < minRatio) return null;
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      final mixed = Color.lerp(fg, target, mid)!;
      if (ratio(mixed) >= minRatio) {
        high = mid;
      } else {
        low = mid;
      }
    }
    // Move one 8-bit step beyond the mathematical boundary. Serialising the
    // exact boundary to #RRGGBB can otherwise round back to the failing side,
    // causing the analyzer and fixer to disagree by a few ten-thousandths.
    return Color.lerp(fg, target, math.min(1, high + 1 / 255))!;
  }

  final dark = candidate(const Color.fromARGB(255, 0, 0, 0));
  final light = candidate(const Color.fromARGB(255, 255, 255, 255));
  if (dark == null && light == null) return foreground;
  if (dark == null) return _hex(light!);
  if (light == null) return _hex(dark);
  return _distanceSquared(fg, dark) <= _distanceSquared(fg, light)
      ? _hex(dark)
      : _hex(light);
}

double _distanceSquared(Color a, Color b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return dr * dr + dg * dg + db * db;
}

String _hex(Color color) {
  int channel(double value) => (value * 255).round().clamp(0, 255);
  String part(double value) => channel(value).toRadixString(16).padLeft(2, '0');
  return '#${part(color.r)}${part(color.g)}${part(color.b)}'.toUpperCase();
}
