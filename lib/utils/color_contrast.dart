// Compatibiliteitsfacade; de kleur- en contrastberekeningen zijn gedeeld.
import 'package:app_appearance/app_appearance.dart' as foundation;
import 'package:material_ui/material_ui.dart';

const double kWcagAaNormalText = foundation.kWcagAaNormalText;
const double kWcagAaLargeText = foundation.kWcagAaLargeText;
const double kWcagCriticalBodyText = foundation.kWcagCriticalBodyText;

Color? tryParseHexColor(String? value) => foundation.tryParseHexColor(value);

double contrastRatio(Color foreground, Color background) =>
    foundation.contrastRatio(foreground, background);

double? hexContrastRatio(String foreground, String background) =>
    foundation.hexContrastRatio(foreground, background);

bool meetsWcagAa(
  String foreground,
  String background, {
  bool largeText = false,
}) => foundation.meetsWcagAa(foreground, background, largeText: largeText);

double? blendedHexContrastRatio(
  String foreground,
  String background, {
  required double foregroundAlpha,
}) => foundation.blendedHexContrastRatio(
  foreground,
  background,
  foregroundAlpha: foregroundAlpha,
);

String nearestContrastingHex(
  String foreground,
  String background, {
  required double minRatio,
  double foregroundAlpha = 1,
}) => foundation.nearestContrastingHex(
  foreground,
  background,
  minRatio: minRatio,
  foregroundAlpha: foregroundAlpha,
);
