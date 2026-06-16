import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Parses a hex colour string (`#RRGGBB` or `RRGGBB`). Returns `null` when
/// invalid so callers can skip the pair instead of throwing.
Color? parseHexColor(String? value) {
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
  final fg = parseHexColor(foreground);
  final bg = parseHexColor(background);
  if (fg == null || bg == null) return null;
  return contrastRatio(fg, bg);
}

/// WCAG 2.1 level AA thresholds.
const double kWcagAaNormalText = 4.5;
const double kWcagAaLargeText = 3.0;

/// Body text below this ratio is treated as a hard quality error.
const double kWcagCriticalBodyText = 3.0;

bool meetsWcagAa(String foreground, String background, {bool largeText = false}) {
  final ratio = hexContrastRatio(foreground, background);
  if (ratio == null) return true;
  final threshold = largeText ? kWcagAaLargeText : kWcagAaNormalText;
  return ratio >= threshold;
}
